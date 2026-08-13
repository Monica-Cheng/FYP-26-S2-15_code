import React, { useEffect, useMemo, useState } from 'react';
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
import ModalDialog from '../components/ui/ModalDialog';
import useClientPagination from '../hooks/useClientPagination';
import { toDate, formatDate } from '../utils/dateUtils';
import { getCallableErrorMessage } from '../utils/planUtils';

const DELETE_CONFIRMATION = 'DELETE POST';

const exportValue = (value) => {
  if (value === undefined || value === null || value === '') return '—';
  return value;
};

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
      .wwpo-title-cell__meta {
        margin-top: 3px;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        line-height: 1.4;
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
      .wwpo-feedback-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
        margin-bottom: 16px;
      }
      .wwpo-modal-copy {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwpo-modal-note {
        margin-top: 10px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwa-modal {
        position: fixed;
        inset: 0;
        z-index: 1200;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: rgba(15, 23, 42, 0.58);
        backdrop-filter: blur(2px);
      }
      .wwa-modal__panel {
        width: min(100%, 560px);
        max-height: calc(100vh - 48px);
        overflow: auto;
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: 20px;
        box-shadow: var(--ww-shadow-lg);
      }
      .wwa-modal__header,
      .wwa-modal__footer {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
        padding: 18px 20px;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwa-modal__footer {
        align-items: center;
        justify-content: flex-end;
        border-top: 1px solid var(--ww-divider);
        border-bottom: 0;
        flex-wrap: wrap;
      }
      .wwa-modal__header-main {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .wwa-modal__title {
        margin: 0;
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-primary-dark);
      }
      .wwa-modal__description {
        margin: 0;
        font-size: var(--ww-type-body-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwa-modal__body {
        padding: 20px;
      }
      @media (max-width: 1160px) {
        .wwpo-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      @media (max-width: 720px) {
        .wwa-modal {
          padding: 12px;
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

const isWorkoutPost = (post) => (post?.type || '').toLowerCase() === 'workout';

const postTitle = (post) => {
  if (isWorkoutPost(post)) {
    return post?.sessionName || post?.caption || 'Workout session';
  }

  return post?.foodName || post?.caption || 'Untitled post';
};

const postSecondaryText = (post) => {
  const caption = (post?.caption || '').trim();
  const primary = postTitle(post);

  if (!caption || caption === primary) {
    return null;
  }

  return caption;
};

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
  const [actionError, setActionError] = useState('');
  const [actionSuccess, setActionSuccess] = useState('');
  const [deletePostId, setDeletePostId] = useState(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [moderationTarget, setModerationTarget] = useState(null);
  const [moderating, setModerating] = useState(false);

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
      setLoadError(getCallableErrorMessage(err, 'Failed to load posts dashboard.'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPosts();
  }, []);

  const openPostDetails = (postId) => {
    setSelectedPostId(postId);
    setActionError('');
  };

  const openPostEditor = (postId) => {
    setSelectedPostId(postId);
    setEditNonce((value) => value + 1);
    setActionError('');
  };

  const openModerationModal = (postId, nextHidden) => {
    setDeletePostId(null);
    setDeleteConfirmation('');
    setModerationTarget({ postId, nextHidden });
    setActionError('');
  };

  const closeModerationModal = () => {
    if (moderating) return;
    setModerationTarget(null);
  };

  const openDeleteModal = (postId) => {
    setModerationTarget(null);
    setDeletePostId(postId);
    setDeleteConfirmation('');
    setActionError('');
  };

  const closeDeleteModal = () => {
    if (deleting) return;
    setDeletePostId(null);
    setDeleteConfirmation('');
  };

  const toggleHidden = async (postId, nextHidden) => {
    const adminSetPostHidden = httpsCallable(functions, 'adminSetPostHidden');

    try {
      setModerating(true);
      setActionError('');
      setActionSuccess('');

      await adminSetPostHidden({
        postId,
        isHidden: nextHidden,
      });

      setPosts((prev) =>
        prev.map((post) =>
          post.id === postId
            ? { ...post, isHidden: nextHidden }
            : post
        )
      );

      setModerationTarget(null);
      setActionSuccess(nextHidden ? 'Post hidden successfully.' : 'Post visibility restored.');
    } catch (err) {
      console.error('Failed to update post visibility:', err);
      const message = getCallableErrorMessage(err, 'Failed to update post visibility. Please try again.');
      setActionError(message);
      throw new Error(message);
    } finally {
      setModerating(false);
    }
  };

  const handleDelete = async (postId) => {
    const adminDeletePost = httpsCallable(functions, 'adminDeletePost');

    try {
      setDeleting(true);
      setActionError('');
      setActionSuccess('');

      await adminDeletePost({
        postId,
        confirmation: DELETE_CONFIRMATION,
      });

      setPosts((prev) => prev.filter((postItem) => postItem.id !== postId));
      setSelectedPostId((prev) => (prev === postId ? null : prev));
      setDeletePostId(null);
      setDeleteConfirmation('');
      setActionSuccess('Post deleted successfully.');
    } catch (err) {
      console.error('Failed to delete post:', err);
      const message = getCallableErrorMessage(err, 'Failed to delete post. Please try again.');
      setActionError(message);
      throw new Error(message);
    } finally {
      setDeleting(false);
    }
  };

  const handleSavePost = async (postId, changes) => {
    const adminUpdatePost = httpsCallable(functions, 'adminUpdatePost');

    try {
      setActionError('');
      setActionSuccess('');

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

      setActionSuccess('Post updated successfully.');
    } catch (err) {
      console.error('Failed to update post:', err);
      const message = getCallableErrorMessage(err, 'Failed to update post. Please try again.');
      setActionError(message);
      throw new Error(message);
    }
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

  const filtered = useMemo(() => {
    return posts.filter((post) => {
      const query = search.toLowerCase();
      const matchesSearch =
        !query ||
        (post.authorName || '').toLowerCase().includes(query) ||
        (post.foodName || '').toLowerCase().includes(query) ||
        (post.sessionName || '').toLowerCase().includes(query) ||
        (post.caption || '').toLowerCase().includes(query);
      const matchesType = typeFilter === 'all' || post.type === typeFilter;
      const isHidden = !!post.isHidden;
      const matchesStatus =
        statusFilter === 'all' ||
        (statusFilter === 'hidden' ? isHidden : !isHidden);

      let matchesDate = true;
      if (dateFilter !== 'all') {
        const created = toDate(post.createdAt);

        if (!created) {
          matchesDate = false;
        } else {
          const now = new Date();
          const daysAgo = (now - created) / (1000 * 60 * 60 * 24);

          if (dateFilter === 'today') {
            matchesDate = created.toDateString() === now.toDateString();
          } else if (dateFilter === '7days') {
            matchesDate = daysAgo <= 7;
          } else if (dateFilter === '30days') {
            matchesDate = daysAgo <= 30;
          }
        }
      }

      return matchesSearch && matchesType && matchesStatus && matchesDate;
    });
  }, [posts, search, typeFilter, statusFilter, dateFilter]);

  const postsPagination = useClientPagination(filtered, {
    resetKey: [search, typeFilter, statusFilter, dateFilter].join('|'),
  });

  const selectedPost = posts.find((post) => post.id === selectedPostId) || null;
  const moderationPostTarget = posts.find((post) => post.id === moderationTarget?.postId) || null;

  const handleExport = () => {
    const rows = filtered.map((post) => ({
      'Post ID': post.id,
      Author: exportValue(post.authorName),
      'Author UID': exportValue(post.uid),
      Type: exportValue(post.type),
      Status: post.isHidden ? 'Hidden' : 'Visible',
      'Created At': formatDate(post.createdAt),
      Caption: exportValue(post.caption),
      'Food Name': isWorkoutPost(post) ? '—' : exportValue(post.foodName),
      'Session Name': isWorkoutPost(post) ? exportValue(post.sessionName) : '—',
      'Is Cardio': isWorkoutPost(post) ? (post.isCardio ? 'Yes' : 'No') : '—',
      'Cardio Activity': isWorkoutPost(post) ? exportValue(post.cardioActivity) : '—',
      'Elapsed Seconds': isWorkoutPost(post) ? (post.elapsedSeconds ?? '—') : '—',
      'Total Sets': isWorkoutPost(post) && !post.isCardio ? (post.totalSets ?? '—') : '—',
      Volume: isWorkoutPost(post) && !post.isCardio ? (post.volume ?? '—') : '—',
      Calories: post.calories ?? '—',
      'Protein (g)': post.proteinG ?? '—',
      'Carbs (g)': post.carbsG ?? '—',
      'Fat (g)': post.fatG ?? '—',
      Reactions: post.reactionCount ?? 0,
      Comments: post.commentCount ?? 0,
      'Moderated At': formatDate(post.moderationUpdatedAt),
      'Moderated By': exportValue(post.moderatedByAdminUid),
      'Admin Updated At': formatDate(post.adminUpdatedAt),
      'Admin Updated By': exportValue(post.updatedByAdminUid),
      'Has Image': post.imageBase64 ? 'Yes' : 'No',
    }));

    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 22 }, { wch: 20 }, { wch: 22 }, { wch: 12 }, { wch: 12 }, { wch: 20 },
      { wch: 30 }, { wch: 20 }, { wch: 22 }, { wch: 10 }, { wch: 18 }, { wch: 16 },
      { wch: 12 }, { wch: 12 }, { wch: 10 }, { wch: 12 }, { wch: 10 }, { wch: 10 },
      { wch: 10 }, { wch: 10 }, { wch: 20 }, { wch: 24 }, { wch: 20 }, { wch: 24 },
      { wch: 10 },
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
        const secondary = postSecondaryText(post);

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
            {isHidden ? 'Hidden' : 'Visible'}
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
            {(actionSuccess || actionError) ? (
              <div className="wwpo-feedback-stack">
                {actionSuccess ? (
                  <div className="wwa-status-pill">
                    <span className="wwa-status-dot" />
                    {actionSuccess}
                  </div>
                ) : null}
                {actionError ? <div className="wwa-alert-error">{actionError}</div> : null}
              </div>
            ) : null}

            <FilterBar
              search={
                <SearchInput
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  onClear={() => setSearch('')}
                  placeholder="Search by author, food name, session name, or caption…"
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
                      { value: 'active', label: 'Status: Visible' },
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
              rows={postsPagination.paginatedItems}
              getRowKey={(post) => post.id}
              selectedRowKey={selectedPostId}
              onRowClick={(post) => openPostDetails(post.id)}
              minWidth={920}
              pagination={{
                currentPage: postsPagination.currentPage,
                pageSize: postsPagination.pageSize,
                totalItems: postsPagination.totalItems,
                totalPages: postsPagination.totalPages,
                pageSizeOptions: postsPagination.pageSizeOptions,
                onPageChange: postsPagination.setCurrentPage,
                onPageSizeChange: postsPagination.setPageSize,
              }}
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
                      onClick={(event) => {
                        event.stopPropagation();
                        openPostDetails(post.id);
                      }}
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
                          onSelect: () => openModerationModal(post.id, !isHidden),
                        },
                        { type: 'divider' },
                        {
                          key: 'delete',
                          label: 'Delete',
                          tone: 'danger',
                          icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openDeleteModal(post.id),
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
              onRequestToggleHidden={(postId, nextHidden) => openModerationModal(postId, nextHidden)}
              onRequestDelete={openDeleteModal}
            />
          ) : null}
        </div>
      )}

      <ModalDialog
        open={Boolean(moderationTarget)}
        title={moderationTarget?.nextHidden ? 'Hide Post' : 'Restore Post Visibility'}
        description={
          moderationTarget?.nextHidden
            ? 'This post will no longer appear in user-facing feeds.'
            : 'This post will become visible in user-facing feeds again.'
        }
        onClose={closeModerationModal}
        footer={(
          <>
            <button type="button" className="wwa-btn wwa-btn-secondary" onClick={closeModerationModal} disabled={moderating}>
              Cancel
            </button>
            <button
              type="button"
              className={`wwa-btn ${moderationTarget?.nextHidden ? 'wwa-btn-danger' : 'wwa-btn-primary'}`}
              onClick={() => toggleHidden(moderationTarget.postId, moderationTarget.nextHidden)}
              disabled={moderating}
            >
              {moderating
                ? (moderationTarget?.nextHidden ? 'Hiding...' : 'Updating...')
                : (moderationTarget?.nextHidden ? 'Hide Post' : 'Unhide Post')}
            </button>
          </>
        )}
      >
        <div className="wwpo-modal-copy">
          {moderationPostTarget ? `Update "${postTitle(moderationPostTarget)}"?` : ''}
        </div>
      </ModalDialog>

      <ModalDialog
        open={Boolean(deletePostId)}
        title="Delete Post"
        description="This permanently removes the post, including its comments and reactions."
        onClose={closeDeleteModal}
        footer={(
          <>
            <button type="button" className="wwa-btn wwa-btn-secondary" onClick={closeDeleteModal} disabled={deleting}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={() => handleDelete(deletePostId)}
              disabled={deleting || deleteConfirmation !== DELETE_CONFIRMATION}
            >
              {deleting ? 'Deleting...' : 'Delete Post'}
            </button>
          </>
        )}
      >
        <div className="wwpo-modal-copy">
          Delete this post permanently?
        </div>
        <div className="wwpo-modal-note">Confirmation</div>
        <input
          className="wwa-input"
          value={deleteConfirmation}
          onChange={(event) => setDeleteConfirmation(event.target.value)}
          placeholder={DELETE_CONFIRMATION}
          autoFocus
        />
      </ModalDialog>
    </div>
  );
}

export default Posts;
