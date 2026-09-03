import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

NostrEvent event({
  required String id,
  required int kind,
  required int createdAt,
  required List<List<String>> tags,
  String pubkey = owner,
  String content = '',
}) => NostrEvent(
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: kind,
  tags: tags,
  content: content,
  sig: '',
);

void main() {
  test('keeps every listed repository including unresolved colon d-tags', () {
    final colonAddress =
        '${EventKind.repositoryAnnouncement}:$owner:team:mobile';
    final missingAddress = '${EventKind.repositoryAnnouncement}:$owner:missing';
    final projects = buildProjectModels(
      projectEvents: [
        event(
          id: 'project',
          kind: EventKind.projectAnnouncement,
          createdAt: 100,
          tags: [
            ['d', 'mobile'],
            ['name', 'Mobile'],
            ['buzz-visibility', 'listed'],
            ['a', colonAddress],
            ['a', missingAddress],
          ],
        ),
      ],
      repositoryEvents: [
        event(
          id: 'repository',
          kind: EventKind.repositoryAnnouncement,
          createdAt: 90,
          tags: [
            ['d', 'team:mobile'],
            ['name', 'Buzz Mobile'],
            ['buzz-channel', 'channel-one'],
          ],
        ),
      ],
    );

    expect(projects, hasLength(1));
    expect(projects.single.name, 'Mobile');
    expect(projects.single.repositories, hasLength(2));
    expect(projects.single.repositories.first.coordinate.dtag, 'team:mobile');
    expect(projects.single.repositories.first.name, 'Buzz Mobile');
    expect(projects.single.repositories.first.channelId, 'channel-one');
    expect(projects.single.repositories.last.isAvailable, isFalse);
    expect(projects.single.repositories.last.name, 'Repository unavailable');
  });

  test('propagates exact project review authority to member repositories', () {
    const coordinator =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const jari =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    const ania =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    final repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';
    final projects = buildProjectModels(
      projectEvents: [
        event(
          id: 'project-authority',
          kind: EventKind.projectAnnouncement,
          createdAt: 100,
          tags: [
            ['d', 'app'],
            ['a', repositoryAddress],
            ['review-coordinator', coordinator],
            ['review-human', jari],
            ['review-human', ania],
          ],
        ),
      ],
      repositoryEvents: [
        event(
          id: 'repository',
          kind: EventKind.repositoryAnnouncement,
          createdAt: 90,
          tags: const [
            ['d', 'app'],
          ],
        ),
      ],
    );

    expect(projects.single.reviewAuthority?.coordinatorPubkeys, [coordinator]);
    expect(projects.single.reviewAuthority?.humanPubkeys, [jari, ania]);
    expect(
      projects.single.repositories.single.reviewAuthority,
      projects.single.reviewAuthority,
    );
  });

  test(
    'treats missing visibility as listed and excludes explicit unlisted',
    () {
      final projects = buildProjectModels(
        projectEvents: [
          event(
            id: 'listed',
            kind: EventKind.projectAnnouncement,
            createdAt: 100,
            tags: const [
              ['d', 'listed'],
              ['buzz-visibility', 'listed'],
            ],
          ),
          event(
            id: 'unlisted',
            kind: EventKind.projectAnnouncement,
            createdAt: 101,
            tags: const [
              ['d', 'unlisted'],
              ['buzz-visibility', 'unlisted'],
            ],
          ),
          event(
            id: 'implicit-listed',
            kind: EventKind.projectAnnouncement,
            createdAt: 102,
            tags: const [
              ['d', 'implicit-listed'],
            ],
          ),
        ],
        repositoryEvents: const [],
      );

      expect(projects.map((project) => project.dtag), [
        'implicit-listed',
        'listed',
      ]);
    },
  );
}
