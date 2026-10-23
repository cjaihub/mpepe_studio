# Social Graph Inventory

## Core Relationships Data Model
- **Location**: `lib/backend/social/models/relationship.dart`
- **Fields**: `id`, `followerId`, `followingId`, `status`, `createdAt`.
- **Status Types**: `pending`, `accepted`, `blocked`, `muted`, `restricted`.

## Content Model
- **Location**: `lib/backend/social/models/post.dart`
- **Types**: `text`, `image`, `carousel`, `reel`, `short`, `live`.
- **Engagement**: Counts for reactions, comments, shares, and views.
- **Algorithmic Ranking**: Utilizes an `algorithmicScore` pre-calculated for feed delivery.

## Interaction Models
- Supports mentions, reactions, and comments (referenced by standalone model files in `lib/backend/social/models/`).
- Feed aggregation connects user relationships and algorithmic scores to generate personalized feeds (`SocialFeedScreen`).

## External Social Graph
- Connects to TikTok and Meta to import or manage cross-platform audiences, configured via wizards in `lib/social_hub/`.
