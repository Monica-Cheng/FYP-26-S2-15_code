import React, { useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import { Download, Eye, EyeOff, Pencil, Trash2 } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import PostDetailPanel from '../components/PostDetailPanel';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import SelectField from '../components/ui/SelectField';
import DataTable from '../components/ui/DataTable';
import TableActions from '../components/ui/TableActions';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import { toDate, formatDate } from '../utils/dateUtils';

function PostsStyles() {
  return (
    <style>{`
      .wwpo-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwpo-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwpo-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
      }
      .wwpo-table .wwa-table th:last-child,
      .wwpo-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwpo-title-cell,
      .wwpo-author-cell {
        min-width: 0;
      }
      .wwpo-title-cell__title,
      .wwpo-author-cell__name {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
        line-height: 1.35;
      }
      .wwpo-title-cell__meta,
      .wwpo-author-cell__meta {
        margin-top: 3px;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        line-height: 1.4;
      }
      .wwpo-title-cell__meta {
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .wwpo-engagement {
        color: var(--ww-text-sec);
        white-space: nowrap;
      }
      .wwpo-inline-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        white-space: nowrap;
      }
      @media (max-width: 1160px) {
        .wwpo-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

const typeTone = (type) => {
  const value = (type || '').toLowerCase();
  if (value.includes('meal')) return 'brand';
  if (value.includes('workout')) return 'neutral';
  return 'neutral';
};

const statusTone = (isHidden) => (isHidden ? 'warning' : 'success');

const postTitle = (post) => post.foodName || post.caption || 'Untitled post';

function Posts() {
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [dateFilter, setDateFilter] = useState('all');
  const [selectedPostId, setSelectedPostId] = useState(null);
  const [editNonce, setEditNonce] = useState(0);

  const fetchPosts = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminListPostsDashboard = httpsCallable(functions, 'adminListPostsDashboard');
      const result = await adminListPostsDashboard();
      const data = result.data || {};
      setPosts(Array.isArray(data.posts) ? data.posts : []);
    } catch (err) {
      console.error('Failed to load posts dashboard:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setLoadError(`Failed to load posts dashboard.${detail}`);
      window.alert(`Failed to load posts dashboard.${detail}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPosts();
  }, []);

  const openPostDetails = (postId) => {
    setSelectedPostId(postId);
  };

  const openPostEditor = (postId) => {
    setSelectedPostId(postId);
    setEditNonce((value) => value + 1);
  };

  // Missing isHidden is treated as Active — matches the mobile app's own
  // absence-as-default convention (e.g. onboardingComplete, healthConnected).
  const toggleHidden = async (postId, currentlyHidden) => {
    const isHidden = !currentlyHidden;
    const adminSetPostHidden = httpsCallable(functions, 'adminSetPostHidden');

    await adminSetPostHidden({
      postId,
      isHidden,
    });

    setPosts((prev) =>
      prev.map((post) =>
        post.id === postId
          ? { ...post, isHidden }
          : post
      )
    );
  };

  const handleDelete = async (postId) => {
    const post = posts.find((item) => item.id === postId);
    const label = post?.foodName || post?.caption || postId;

    const confirmation = window.prompt(
      `Permanently delete this post?\n\n` +
      `"${label}"\n\n` +
      'Its reactions and comments will also be removed.\n\n' +
      'Type DELETE POST exactly to continue:'
    );

    if (confirmation !== 'DELETE POST') return;

    const adminDeletePost = httpsCallable(functions, 'adminDeletePost');

    await adminDeletePost({
      postId,
      confirmation,
    });

    setPosts((prev) => prev.filter((postItem) => postItem.id !== postId));
    setSelectedPostId((prev) => (prev === postId ? null : prev));
  };

  const handleSavePost = async (postId, changes) => {
    const adminUpdatePost = httpsCallable(functions, 'adminUpdatePost');

    const result = await adminUpdatePost({
      postId,
      changes,
    });

    const savedChanges = result.data?.changes || changes;

    setPosts((prev) =>
      prev.map((post) =>
        post.id === postId
          ? { ...post, ...savedChanges }
          : post
      )
    );
  };

  const types = Array.from(new Set(posts.map((post) => post.type).filter(Boolean))).sort();

  const hasActiveFilters = Boolean(
    search || typeFilter !== 'all' || statusFilter !== 'all' || dateFilter !== 'all'
  );

  const resetFilters = () => {
    setSearch('');
    setTypeFilter('all');
    setStatusFilter('all');
    setDateFilter('all');
  };

  const matchesDateFilter = (post) => {
    if (dateFilter === 'all') return true;

    const created = toDate(post.createdAt);
    if (!created) return false;

    const now = new Date();
    const daysAgo = (now - created) / (1000 * 60 * 60 * 24);

    if (dateFilter === 'today') {
      return created.toDateString() === now.toDateString();
    }
    if (dateFilter === '7days') return daysAgo <= 7;
    if (dateFilter === '30days') return daysAgo <= 30;
    return true;
  };

  const filtered = posts.filter((post) => {
    const query = search.toLowerCase();
    const matchesSearch =
      !query ||
      (post.authorName || '').toLowerCase().includes(query) ||
      (post.foodName || '').toLowerCase().includes(query) ||
      (post.caption || '').toLowerCase().includes(query);
    const matchesType = typeFilter === 'all' || post.type === typeFilter;
    const isHidden = !!post.isHidden;
    const matchesStatus =
      statusFilter === 'all' ||
      (statusFilter === 'hidden' ? isHidden : !isHidden);

    return matchesSearch && matchesType && matchesStatus && matchesDateFilter(post);
  });

  const selectedPost = posts.find((post) => post.id === selectedPostId) || null;

  const handleExport = () => {
    const rows = filtered.map((post) => ({
      'Post ID': post.id,
      Author: post.authorName || '—',
      'User UID': post.uid || '—',
      'Food Name': post.foodName || '—',
      Caption: post.caption || '—',
      Type: post.type || '—',
      Calories: post.calories ?? '—',
      'Protein (g)': post.proteinG ?? '—',
      'Carbs (g)': post.carbsG ?? '—',
      'Fat (g)': post.fatG ?? '—',
      Reactions: post.reactionCount ?? 0,
      Comments: post.commentCount ?? 0,
      Status: post.isHidden ? 'Hidden' : 'Active',
      'Created Date': formatDate(post.createdAt),
    }));

    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 22 }, { wch: 20 }, { wch: 22 }, { wch: 20 }, { wch: 30 }, { wch: 12 },
      { wch: 10 }, { wch: 12 }, { wch: 10 }, { wch: 10 }, { wch: 10 }, { wch: 10 },
      { wch: 10 }, { wch: 20 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Posts');
    XLSX.writeFile(workbook, 'WiseWorkout_Posts.xlsx');
  };

  const columns = [
    {
      key: 'post',
      header: 'Post',
      render: (post) => {
        const title = postTitle(post);
        const secondary =
          post.foodName && post.caption
            ? post.caption
            : null;

        return (
          <div className="wwpo-title-cell">
            <div className="wwpo-title-cell__title">{title}</div>
            {secondary ? <div className="wwpo-title-cell__meta">{secondary}</div> : null}
          </div>
        );
      },
    },
    {
      key: 'author',
      header: 'Author',
      render: (post) => (
        <div className="wwpo-author-cell">
          <div className="wwpo-author-cell__name">{post.authorName || '—'}</div>
          {post.uid ? <div className="wwpo-author-cell__meta">{post.uid}</div> : null}
        </div>
      ),
    },
    {
      key: 'type',
      header: 'Type',
      render: (post) => <Badge tone={typeTone(post.type)}>{post.type || '—'}</Badge>,
    },
    {
      key: 'engagement',
      header: 'Engagement',
      render: (post) => (
        <span className="wwpo-engagement">
          {post.reactionCount ?? 0} reactions · {post.commentCount ?? 0} comments
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (post) => {
        const isHidden = !!post.isHidden;
        return (
          <Badge tone={statusTone(isHidden)}>
            {isHidden ? 'Hidden' : 'Active'}
          </Badge>
        );
      },
    },
    {
      key: 'created',
      header: 'Created',
      render: (post) => formatDate(post.createdAt),
    },
  ];

  const typeOptions = [{ value: 'all', label: 'Type: All' }, ...types.map((value) => ({ value, label: value }))];

  return (
    <div className="wwpo-page">
      <AdminStyles />
      <PostsStyles />

      <PageHeader
        title="Posts"
        description="Manage community and nutrition content"
        count={loading ? undefined : `${posts.length} total posts`}
        actions={
          <button
            type="button"
            className="wwa-btn wwa-btn-secondary"
            onClick={handleExport}
            disabled={loading || filtered.length === 0}
          >
            <Download aria-hidden="true" size={16} strokeWidth={2} />
            Export to Excel
          </button>
        }
      />

      {loading ? (
        <LoadingState rows={6} />
      ) : loadError ? (
        <ErrorState
          title="Failed to load posts"
          message={loadError}
          onRetry={fetchPosts}
        />
      ) : (
        <div className={`wwpo-layout ${selectedPost ? 'has-detail' : ''}`}>
          <div>
            <FilterBar
              search={
                <SearchInput
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  onClear={() => setSearch('')}
                  placeholder="Search by author, food name, or caption…"
                  label="Search posts"
                />
              }
              filters={
                <>
                  <SelectField
                    value={typeFilter}
                    onChange={(event) => setTypeFilter(event.target.value)}
                    options={typeOptions}
                    aria-label="Filter posts by type"
                  />
                  <SelectField
                    value={statusFilter}
                    onChange={(event) => setStatusFilter(event.target.value)}
                    options={[
                      { value: 'all', label: 'Status: All' },
                      { value: 'active', label: 'Status: Active' },
                      { value: 'hidden', label: 'Status: Hidden' },
                    ]}
                    aria-label="Filter posts by status"
                  />
                  <SelectField
                    value={dateFilter}
                    onChange={(event) => setDateFilter(event.target.value)}
                    options={[
                      { value: 'all', label: 'Date: All Time' },
                      { value: 'today', label: 'Date: Today' },
                      { value: '7days', label: 'Date: Last 7 Days' },
                      { value: '30days', label: 'Date: Last 30 Days' },
                    ]}
                    aria-label="Filter posts by date"
                  />
                </>
              }
              onReset={resetFilters}
              resetLabel="Reset filters"
              resetVariant="secondary"
              resetDisabled={!hasActiveFilters}
              count={`${filtered.length} of ${posts.length} posts`}
            />

            <DataTable
              className="wwpo-table"
              columns={columns}
              rows={filtered}
              getRowKey={(post) => post.id}
              selectedRowKey={selectedPostId}
              minWidth={920}
              emptyIcon={null}
              emptyTitle="No posts found"
              emptyMessage={hasActiveFilters ? 'Try adjusting your search or filters.' : 'No posts on the platform yet.'}
              renderRowActions={(post) => {
                const isHidden = !!post.isHidden;

                return (
                  <div className="wwpo-inline-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                      onClick={() => openPostDetails(post.id)}
                      aria-label={`View ${postTitle(post)}`}
                    >
                      <Eye aria-hidden="true" size={14} strokeWidth={2} />
                      View
                    </button>
                    <TableActions
                      label={`Actions for ${postTitle(post)}`}
                      items={[
                        {
                          key: 'edit',
                          label: 'Edit',
                          icon: <Pencil aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openPostEditor(post.id),
                        },
                        {
                          key: 'toggle-hidden',
                          label: isHidden ? 'Unhide' : 'Hide',
                          icon: <EyeOff aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => toggleHidden(post.id, isHidden),
                        },
                        { type: 'divider' },
                        {
                          key: 'delete',
                          label: 'Delete',
                          tone: 'danger',
                          icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => handleDelete(post.id),
                        },
                      ]}
                    />
                  </div>
                );
              }}
            />
          </div>

          {selectedPost ? (
            <PostDetailPanel
              post={selectedPost}
              editNonce={editNonce}
              onClose={() => setSelectedPostId(null)}
              onSave={handleSavePost}
              onToggleHidden={toggleHidden}
              onDelete={handleDelete}
            />
          ) : null}
        </div>
      )}
    </div>
  );
}

export default Posts;
