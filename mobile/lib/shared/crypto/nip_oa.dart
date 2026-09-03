import 'dart:convert';
import 'dart:typed_data';

import 'package:nostr/nostr.dart' as nostr;
import 'package:pointycastle/digests/sha256.dart';

/// NIP-OA (Owner Attestation) — verify the `auth` tag on a kind:0 profile
/// that proves an owner key authorized an agent key.
///
/// Tag format: ["auth", "<owner-pubkey-hex>", "<conditions>", "<sig-hex>"]
/// Preimage:   "nostr:agent-auth:" + agent_pubkey_hex + ":" + conditions
/// Signature:  BIP-340 Schnorr over SHA256(preimage) by the owner key.
///
/// Mirrors `profile_valid_oa_owner_pubkey` in desktop/src-tauri: the tag is
/// verified against the profile event author, so a forged or stale marker
/// cannot turn a person into an agent.
///
/// Returns the owner pubkey (lowercase hex) when the profile has exactly one
/// valid auth tag, or null otherwise.
String? verifiedOaOwnerPubkey(List<List<String>> tags, String agentPubkey) {
  final agent = agentPubkey.toLowerCase();
  final authTags = tags
      .where((tag) => tag.isNotEmpty && tag.first == 'auth')
      .toList();
  if (authTags.length != 1) return null;

  for (final tag in authTags) {
    if (tag.length != 4) continue;

    final owner = tag[1];
    final conditions = tag[2];
    final sig = tag[3];

    // NIP-OA hex encodings are canonical lowercase.
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ||
        !RegExp(r'^[0-9a-f]{128}$').hasMatch(sig)) {
      continue;
    }
    // Self-attestation is meaningless and rejected.
    if (owner == agent) continue;
    if (!_validConditions(conditions)) continue;

    final preimage = utf8.encode('nostr:agent-auth:$agent:$conditions');
    final digest = SHA256Digest().process(Uint8List.fromList(preimage));
    final message = digest
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    try {
      if (nostr.Schnorr.verify(
        publicKey: owner,
        message: message,
        signature: sig,
      )) {
        return owner;
      }
    } catch (_) {
      // Malformed hex — treat as an invalid tag.
    }
  }

  return null;
}

/// Verify an owner attestation and enforce its conditions for one event.
String? verifiedOaOwnerPubkeyForEvent(
  List<List<String>> tags,
  String agentPubkey, {
  required int kind,
  required int createdAt,
}) {
  final authTags = tags
      .where((tag) => tag.isNotEmpty && tag.first == 'auth')
      .toList();
  if (authTags.length != 1) return null;
  for (final tag in authTags) {
    if (tag.length != 4) continue;
    if (!_conditionsAllowEvent(tag[2], kind: kind, createdAt: createdAt)) {
      continue;
    }
    final owner = verifiedOaOwnerPubkey([tag], agentPubkey);
    if (owner != null) return owner;
  }
  return null;
}

/// Validate the NIP-OA `conditions` string: empty, or `&`-joined clauses of
/// `kind=<n>`, `created_at<<n>`, or `created_at><n>` with canonical decimals.
bool _validConditions(String conditions) {
  if (conditions.isEmpty) return true;
  if (conditions.contains(RegExp(r'\s'))) return false;

  for (final clause in conditions.split('&')) {
    final match = RegExp(
      r'^(?:kind=|created_at<|created_at>)(0|[1-9][0-9]*)$',
    ).firstMatch(clause);
    if (match == null) return false;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value > 4294967295) return false;
    if (clause.startsWith('kind=') && value > 65535) return false;
  }

  return true;
}

bool _conditionsAllowEvent(
  String conditions, {
  required int kind,
  required int createdAt,
}) {
  if (!_validConditions(conditions)) return false;
  if (conditions.isEmpty) return true;
  for (final clause in conditions.split('&')) {
    if (clause.startsWith('kind=')) {
      if (kind != int.parse(clause.substring('kind='.length))) return false;
    } else if (clause.startsWith('created_at<')) {
      if (createdAt >= int.parse(clause.substring('created_at<'.length))) {
        return false;
      }
    } else if (clause.startsWith('created_at>')) {
      if (createdAt <= int.parse(clause.substring('created_at>'.length))) {
        return false;
      }
    }
  }
  return true;
}
