// lib/screens/club/friends_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/user_avatar.dart';

// Same comma-grouped XP formatting as club_screen.dart's private _fmtXp() —
// not importable across files (leading underscore), so mirrored here rather
// than reimplemented differently.
String _fmtXp(int xp) {
  if (xp >= 1000) {
    return '${xp ~/ 1000},${(xp % 1000).toString().padLeft(3, '0')}';
  }
  return '$xp';
}

// Full-page Friends screen — search, pending requests, and the friends
// list. Reached via context.push(Routes.friends) from club_screen.dart's
// top-bar icon, and from the friend-request notification deep-link (see
// home_screen.dart / ClubScreen.kFriendsSubtabIndex), which passes
// initialRequestsExpanded via `extra` so the Requests section opens
// already expanded.
class FriendsScreen extends StatefulWidget {
  final bool initialRequestsExpanded;
  const FriendsScreen({super.key, this.initialRequestsExpanded = false});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  String _myName = 'You';
  String _myUsername = '';

  String _searchQuery = '';
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _requestsExpanded = false;
  Timer? _searchDebounce;
  StreamSubscription<List<Map<String, dynamic>>>? _friendsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _friendRequestsSub;

  // Uids we've already sent a pending friend request to, for the current
  // search results — checked once when results load (see _performSearch)
  // and updated optimistically by _sendRequest, rather than re-querying
  // Firestore per row on every rebuild.
  Set<String> _pendingRequestUids = {};

  static const _kDivider = Color(0xFFE8EAF8);

  // WW.cardDecoration without the border/shadow, matching Club tab's
  // simplified card style.
  static const _kFlatListDecoration = BoxDecoration(
    color: WW.card,
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  static const _kSectionHeaderStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: WW.textSec,
    letterSpacing: 0.2,
  );

  @override
  void initState() {
    super.initState();
    _requestsExpanded = widget.initialRequestsExpanded;
    _loadMyName();
    _startFriendStreams();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _friendsSub?.cancel();
    _friendRequestsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMyName() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    final profile = await _firestoreService.getUserProfile(uid);
    final name = profile?['displayName'] as String?;
    final username = profile?['username'] as String?;
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _myName = name;
        _myUsername = username ?? '';
      });
    }
  }

  void _startFriendStreams() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    _friendsSub = _firestoreService.getFriendsStream(uid).listen((friends) {
      if (mounted) setState(() => _friends = friends);
      _enrichWithPhotos(
        friends,
        key: 'uid',
        onDone: (enriched) {
          if (mounted) setState(() => _friends = enriched);
        },
      );
    });
    _friendRequestsSub = _firestoreService.getFriendRequestsStream(uid).listen((
      requests,
    ) {
      if (mounted) setState(() => _friendRequests = requests);
      _enrichWithPhotos(
        requests,
        key: 'requesterUid',
        onDone: (enriched) {
          if (mounted) setState(() => _friendRequests = enriched);
        },
      );
    });
  }

  // The friends/friendRequests subcollection docs are denormalized once at
  // request/accept time (see acceptFriendRequest()/sendFriendRequest()) and
  // never refreshed — so a photo uploaded afterwards wouldn't show up for
  // any friend/request that predates it. Overlays a live photoBase64 from
  // publicProfiles/{uid} onto each row instead, so this works retroactively
  // for existing relationships too, not just new ones.
  Future<void> _enrichWithPhotos(
    List<Map<String, dynamic>> rows, {
    required String key,
    required void Function(List<Map<String, dynamic>>) onDone,
  }) async {
    final uids = rows
        .map((r) => r[key] as String?)
        .whereType<String>()
        .toList();
    if (uids.isEmpty) return;
    final photos = await _firestoreService.getPublicPhotosByUids(uids);
    if (photos.isEmpty) return;
    onDone(
      rows.map((r) {
        final uid = r[key] as String?;
        final photo = uid != null ? photos[uid] : null;
        return photo != null ? {...r, 'photoBase64': photo} : r;
      }).toList(),
    );
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await _firestoreService.searchUsersByUsername(query);
      final myUid = _authService.getCurrentUser()?.uid;
      // Friends are no longer excluded here — they still show up in
      // results, just with a "Friends" label instead of "Add Friend"
      // (see _buildSearchResultRow).
      final filtered = results.where((r) {
        final uid = r['uid'] as String?;
        if (uid == null || uid.isEmpty) return false;
        if (uid == myUid) return false;
        return true;
      }).toList();

      // Check pending-request status once per loaded result set (not per
      // row per rebuild) and cache it in _pendingRequestUids; _sendRequest
      // updates that cache optimistically afterwards instead of
      // re-querying Firestore.
      final pending = <String>{};
      if (myUid != null) {
        for (final r in filtered) {
          final uid = r['uid'] as String;
          final alreadySent = await _firestoreService.hasSentFriendRequest(
            uid,
            myUid,
          );
          if (alreadySent) pending.add(uid);
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = filtered;
          _pendingRequestUids = pending;
          _isSearching = false;
        });
      }
    } catch (e) {
      // Was a bare `catch (_)` that silently discarded the exception,
      // leaving _searchResults untouched — a real error (e.g. a
      // PERMISSION_DENIED from a rules regression) rendered identically
      // to "no results", with nothing printed anywhere to debug from.
      debugPrint('friends_screen: username search failed: $e');
      if (mounted) {
        setState(() => _isSearching = false);
        _snack('Search failed. Please try again.');
      }
    }
  }

  Future<void> _sendRequest(Map<String, dynamic> user) async {
    final myUid = _authService.getCurrentUser()?.uid;
    if (myUid == null) return;
    final toUid = user['uid'] as String?;
    if (toUid == null) return;
    try {
      await _firestoreService.sendFriendRequest(
        myUid,
        _myName,
        _myUsername,
        toUid,
      );
      if (mounted) {
        _snack('Friend request sent');
        // The person stays visible in _searchResults; just mark them as
        // pending instead of re-querying Firestore for their status.
        setState(() {
          _pendingRequestUids = {..._pendingRequestUids, toUid};
        });
      }
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    final myUid = _authService.getCurrentUser()?.uid;
    if (myUid == null) return;
    final requesterUid = request['requesterUid'] as String?;
    if (requesterUid == null) return;
    try {
      await _firestoreService.acceptFriendRequest(
        myUid,
        _myName,
        _myUsername,
        requesterUid,
        request['fromDisplayName'] as String? ?? '',
        request['fromUsername'] as String? ?? '',
      );
      if (mounted) _snack('Friend request accepted');
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _declineRequest(Map<String, dynamic> request) async {
    final myUid = _authService.getCurrentUser()?.uid;
    if (myUid == null) return;
    final requesterUid = request['requesterUid'] as String?;
    if (requesterUid == null) return;
    try {
      await _firestoreService.declineFriendRequest(myUid, requesterUid);
    } catch (_) {}
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: WW.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Neutral avatar treatment shared by every Friends row — WW.elevated +
  // WW.text initial. Duplicated from club_screen.dart's identical helper
  // since Friends is now its own top-level widget/route rather than a
  // method sharing _ClubScreenState; the isMe branch is kept for parity
  // even though nothing here currently passes isMe: true.
  Widget _avatar(String initial, {String? photoBase64, bool isMe = false}) {
    return UserAvatar(
      photoBase64: photoBase64,
      initial: initial,
      size: 40,
      backgroundColor: isMe ? WW.primary : WW.elevated,
      initialColor: isMe ? Colors.white : WW.text,
      initialFontSize: 15,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  // Header matching this app's other full-screen conventions (see
  // settings_screen.dart / profile_screen.dart _buildTopBar()): a 56px
  // WW.card bar with a bottom hairline, centered title, and a rounded
  // icon button — close_rounded here since this page is dismissed back to
  // whichever screen opened it, not stepped back through a stack.
  Widget _buildHeader() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.close_rounded, size: 20, color: WW.textSec),
                ),
              ),
            ),
          ),
          const Text(
            'Friends',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final isSearching = _searchQuery.trim().isNotEmpty;
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: WW.elevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 14, color: WW.text),
              decoration: const InputDecoration(
                hintText: 'Search by username...',
                hintStyle: TextStyle(fontSize: 14, color: WW.textSec),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        Expanded(
          child: isSearching
              ? _buildSearchResultsList()
              : _buildFriendsAndRequestsList(),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    if (_searchResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No users found',
            style: TextStyle(fontSize: 13, color: WW.textSec),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        Text('RESULTS (${_searchResults.length})', style: _kSectionHeaderStyle),
        const SizedBox(height: 10),
        Container(
          decoration: _kFlatListDecoration,
          child: Column(
            children: List.generate(_searchResults.length, (i) {
              return _buildSearchResultRow(
                _searchResults[i],
                isLast: i == _searchResults.length - 1,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultRow(
    Map<String, dynamic> user, {
    required bool isLast,
  }) {
    final name = user['displayName'] as String? ?? 'User';
    final username = user['username'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoBase64 = user['photoBase64'] as String?;
    final uid = user['uid'] as String?;
    final isFriend = uid != null && _friends.any((f) => f['uid'] == uid);
    final isPending = uid != null && _pendingRequestUids.contains(uid);

    Widget trailing;
    if (isFriend) {
      trailing = const Text(
        'Friends',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: WW.textSec,
        ),
      );
    } else if (isPending) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: WW.elevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Requested',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: WW.textSec,
          ),
        ),
      );
    } else {
      trailing = GestureDetector(
        onTap: () => _sendRequest(user),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: WW.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Add Friend',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Row(
        children: [
          _avatar(initial, photoBase64: photoBase64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: WW.rowName),
                const SizedBox(height: 2),
                Text(
                  username.isNotEmpty ? '@$username' : '—',
                  style: WW.rowSecondary,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildFriendsAndRequestsList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        if (_friendRequests.isNotEmpty) ...[
          _buildRequestsHeader(),
          if (_requestsExpanded) ...[
            const SizedBox(height: 10),
            Container(
              decoration: _kFlatListDecoration,
              child: Column(
                children: List.generate(_friendRequests.length, (i) {
                  return _buildRequestRow(
                    _friendRequests[i],
                    isLast: i == _friendRequests.length - 1,
                  );
                }),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
        Text('FRIENDS (${_friends.length})', style: _kSectionHeaderStyle),
        const SizedBox(height: 10),
        if (_friends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No friends yet. Search above to add some!',
                style: TextStyle(fontSize: 13, color: WW.textSec),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          _buildFriendsList(),
      ],
    );
  }

  // Real level + weekly XP per friend — same getFriendsLeaderboardStream()
  // call already used by club_screen.dart's Leaderboard tab and
  // profile_screen.dart's Friends section, keyed here into a uid lookup map
  // since this list just needs it merged onto the existing friend rows
  // (from getFriendsStream(), which only carries uid/displayName/username),
  // not ranked/sorted like the full leaderboard.
  Widget _buildFriendsList() {
    final myUid = _authService.getCurrentUser()?.uid ?? '';
    final friendUids = _friends.map((f) => f['uid'] as String).toList();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getFriendsLeaderboardStream(myUid, friendUids),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: WW.primary)),
          );
        }
        final xpByUid = {
          for (final e in snapshot.data ?? const <Map<String, dynamic>>[])
            e['uid'] as String: e,
        };
        return Container(
          decoration: _kFlatListDecoration,
          child: Column(
            children: List.generate(_friends.length, (i) {
              final f = _friends[i];
              return _buildFriendRow(
                f,
                xpByUid[f['uid'] as String?],
                isLast: i == _friends.length - 1,
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildRequestsHeader() {
    return GestureDetector(
      onTap: () => setState(() => _requestsExpanded = !_requestsExpanded),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'REQUESTS (${_friendRequests.length})',
              style: _kSectionHeaderStyle,
            ),
          ),
          Icon(
            _requestsExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: WW.textSec,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestRow(
    Map<String, dynamic> request, {
    required bool isLast,
  }) {
    final name = request['fromDisplayName'] as String? ?? 'User';
    final username = request['fromUsername'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoBase64 = request['photoBase64'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Row(
        children: [
          _avatar(initial, photoBase64: photoBase64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: WW.rowName),
                const SizedBox(height: 2),
                Text(
                  username.isNotEmpty ? '@$username' : '—',
                  style: WW.rowSecondary,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _declineRequest(request),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: WW.textSec,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _acceptRequest(request),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // [xp] is this friend's entry from getFriendsLeaderboardStream() (see
  // _buildFriendsList()) — null while that stream is still loading or if the
  // friend has no publicProfiles doc at all; level/weeklyXp field extraction
  // and fallbacks mirror club_screen.dart's _buildLeaderRow() exactly
  // (level missing -> '—', weeklyXp missing/absent -> 0, never a dash).
  Widget _buildFriendRow(
    Map<String, dynamic> f,
    Map<String, dynamic>? xp, {
    required bool isLast,
  }) {
    final name = f['displayName'] as String? ?? 'Friend';
    final username = f['username'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoBase64 = f['photoBase64'] as String?;
    final level = (xp?['level'] as num?)?.toInt();
    final levelLabel = level != null ? 'Level $level' : '—';
    final weeklyXp = (xp?['weeklyXp'] as int?) ?? 0;
    // Friends are, by definition, never the current user themselves — no
    // "own row" case to exclude here (unlike club_screen.dart's
    // leaderboard, which always includes the viewer's own row). No
    // existing tap targets on this row (no accept/decline/remove
    // buttons), so the whole row is safe to wrap.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openFriendProfile(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
        ),
        child: Row(
          children: [
            _avatar(initial, photoBase64: photoBase64),
            const SizedBox(width: 12),
            // Name, username · level
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: WW.rowName),
                  const SizedBox(height: 2),
                  Text(
                    username.isNotEmpty ? '@$username · $levelLabel' : levelLabel,
                    style: WW.rowSecondary,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_fmtXp(weeklyXp)} XP', style: WW.rowStat),
                const SizedBox(height: 2),
                const Text('Weekly XP', style: WW.rowSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Same navigation FeedPostCard's avatar/name already uses (see its own
  // _openProfile()) — Routes.userProfile with uid/authorName via `extra`.
  void _openFriendProfile(Map<String, dynamic> f) {
    final uid = f['uid'] as String?;
    if (uid == null || uid.isEmpty) return;
    context.push(
      Routes.userProfile,
      extra: {
        'uid': uid,
        'authorName': f['displayName'] as String?,
      },
    );
  }
}
