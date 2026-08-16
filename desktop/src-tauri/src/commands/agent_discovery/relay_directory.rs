//! Relay-backed shared-agent directory discovery.

use tauri::State;

use crate::{
    app_state::AppState, commands::identity_archive, managed_agents::RelayAgentInfo, nostr_convert,
    relay::query_relay,
};

const RELAY_DIRECTORY_PAGE_SIZE: usize = 500;
const RELAY_FILTER_BATCH_SIZE: usize = 10;

fn exact_author_filters(pubkeys: &[String], kind: u16) -> Vec<serde_json::Value> {
    pubkeys
        .iter()
        .map(|pubkey| {
            serde_json::json!({
                "authors": [pubkey],
                "kinds": [kind],
                "limit": 1,
            })
        })
        .collect()
}

fn managed_policy_filters(
    candidate_pubkeys: &[String],
    verified_owners: &std::collections::HashMap<String, String>,
) -> Vec<serde_json::Value> {
    candidate_pubkeys
        .iter()
        .filter_map(|agent_pubkey| {
            verified_owners.get(agent_pubkey).map(|owner_pubkey| {
                serde_json::json!({
                    "authors": [owner_pubkey],
                    "kinds": [30177],
                    "#d": [agent_pubkey],
                    "limit": 1,
                })
            })
        })
        .collect()
}

fn current_user_pubkey(state: &AppState) -> Result<String, String> {
    state
        .keys
        .lock()
        .map(|keys| keys.public_key().to_hex())
        .map_err(|error| error.to_string())
}

pub(super) fn advance_relay_cursor(filter: &mut serde_json::Value, page: &[nostr::Event]) {
    let last = page
        .last()
        .expect("a full relay page always has a last event");
    filter["until"] = serde_json::json!(last.created_at.as_secs());
    filter["before_id"] = serde_json::json!(last.id.to_hex());
}

async fn query_all_relay_pages(
    state: &AppState,
    mut filter: serde_json::Value,
) -> Result<Vec<nostr::Event>, String> {
    filter["limit"] = serde_json::json!(RELAY_DIRECTORY_PAGE_SIZE);
    let mut events = Vec::new();
    loop {
        let page = query_relay(state, &[filter.clone()]).await?;
        let done = page.len() < RELAY_DIRECTORY_PAGE_SIZE;
        if !done {
            advance_relay_cursor(&mut filter, &page);
        }
        events.extend(page);
        if done {
            return Ok(events);
        }
    }
}

#[tauri::command]
pub async fn list_relay_agents(state: State<'_, AppState>) -> Result<Vec<RelayAgentInfo>, String> {
    let viewer_pubkey = current_user_pubkey(&state)?;
    let relay_pubkey = identity_archive::fetch_relay_self(&state)
        .await?
        .ok_or_else(|| "relay agent membership authority is unavailable".to_string())?;

    // Membership is the authoritative and bounded candidate source. Only
    // channels visible to this identity are read, and only bot-role p-tags can
    // drive the downstream managed-policy and owner-profile lookups.
    let membership_events = query_all_relay_pages(
        &state,
        serde_json::json!({
            "kinds": [39002],
            "authors": [&relay_pubkey],
            "#p": [&viewer_pubkey],
        }),
    )
    .await
    .map_err(|error| format!("relay agent channel-membership query failed: {error}"))?;
    let member_agent_channel_ids =
        nostr_convert::member_agent_channel_ids_from_events(&membership_events, &relay_pubkey);
    let candidate_pubkeys: Vec<String> = member_agent_channel_ids.keys().cloned().collect();
    if candidate_pubkeys.is_empty() {
        return Ok(Vec::new());
    }

    let mut directory_events = Vec::new();
    let mut profile_events = Vec::new();
    let directory_filters = exact_author_filters(&candidate_pubkeys, 10100);
    let profile_filters = exact_author_filters(&candidate_pubkeys, 0);
    for filter_offset in (0..candidate_pubkeys.len()).step_by(RELAY_FILTER_BATCH_SIZE) {
        let filter_end = (filter_offset + RELAY_FILTER_BATCH_SIZE).min(candidate_pubkeys.len());
        let (directory, profiles) = tokio::join!(
            query_relay(&state, &directory_filters[filter_offset..filter_end]),
            query_relay(&state, &profile_filters[filter_offset..filter_end]),
        );
        directory_events.extend(
            directory
                .map_err(|error| format!("relay agent runtime-directory query failed: {error}"))?,
        );
        profile_events.extend(
            profiles.map_err(|error| format!("relay agent owner-profile query failed: {error}"))?,
        );
    }

    // Only the agent's signed NIP-OA profile can name the owner coordinate to
    // query. Each exact `(owner, d=agent)` filter returns at most one current
    // replaceable event, so forged 30177 coordinates cannot amplify or crowd
    // the authentic policy out of a bounded result page.
    let verified_owners = nostr_convert::verified_agent_owners_from_profiles(&profile_events);
    let managed_filters = managed_policy_filters(&candidate_pubkeys, &verified_owners);
    let mut managed_agent_events = Vec::new();
    for filters in managed_filters.chunks(RELAY_FILTER_BATCH_SIZE) {
        managed_agent_events.extend(
            query_relay(&state, filters)
                .await
                .map_err(|error| format!("relay agent managed-policy query failed: {error}"))?,
        );
    }

    let mut agents = nostr_convert::relay_agents_from_directory_events(
        &directory_events,
        &managed_agent_events,
        &profile_events,
    );
    agents.retain(|agent| member_agent_channel_ids.contains_key(&agent.pubkey));
    for agent in &mut agents {
        agent.channel_ids = member_agent_channel_ids
            .get(&agent.pubkey)
            .cloned()
            .unwrap_or_default();
    }
    Ok(agents)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_author_queries_prevent_noisy_agent_crowd_out() {
        let pubkeys = vec!["a".repeat(64), "b".repeat(64)];

        let filters = exact_author_filters(&pubkeys, 10100);

        assert_eq!(filters.len(), 2);
        for (filter, pubkey) in filters.iter().zip(pubkeys) {
            assert_eq!(filter["authors"], serde_json::json!([pubkey]));
            assert_eq!(filter["kinds"], serde_json::json!([10100]));
            assert_eq!(filter["limit"], 1);
        }
    }

    #[test]
    fn managed_policy_queries_are_exact_coordinates() {
        let candidates = vec!["a".repeat(64), "b".repeat(64)];
        let owners = std::collections::HashMap::from([
            (candidates[0].clone(), "c".repeat(64)),
            (candidates[1].clone(), "d".repeat(64)),
        ]);

        let filters = managed_policy_filters(&candidates, &owners);

        assert_eq!(filters.len(), 2);
        for (filter, candidate) in filters.iter().zip(candidates) {
            assert_eq!(filter["authors"].as_array().map(Vec::len), Some(1));
            assert_eq!(filter["kinds"], serde_json::json!([30177]));
            assert_eq!(filter["#d"], serde_json::json!([candidate]));
            assert_eq!(filter["limit"], 1);
        }
    }

    #[test]
    fn relay_filter_batches_do_not_exceed_protocol_limit() {
        let pubkeys: Vec<_> = (0..25).map(|index| format!("{index:064x}")).collect();
        let filters = exact_author_filters(&pubkeys, 0);

        let batch_sizes: Vec<_> = filters
            .chunks(RELAY_FILTER_BATCH_SIZE)
            .map(<[_]>::len)
            .collect();

        assert_eq!(batch_sizes, vec![10, 10, 5]);
    }
}
