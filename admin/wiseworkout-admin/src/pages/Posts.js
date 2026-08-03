import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, doc, updateDoc, deleteDoc } from 'firebase/firestore';
import * as XLSX from 'xlsx';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import PostDetailPanel from '../components/PostDetailPanel';
import { toDate, formatDate } from '../utils/dateUtils';

function Posts() {
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [dateFilter, setDateFilter] = useState('all');
  const [selectedPostId, setSelectedPostId] = useState(null);

  useEffect(() => {
    const fetchPosts = async () => {
      try {
        const snap = await getDocs(collection(db, 'posts'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setPosts(data);
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchPosts();
  }, []);

  // Missing isHidden is treated as Active — matches the mobile app's own
  // absence-as-default convention (e.g. onboardingComplete, healthConnected).
  const toggleHidden = async (postId, currentlyHidden) => {
    const isHidden = !currentlyHidden;
    await updateDoc(doc(db, 'posts', postId), { isHidden });
    setPosts(prev => prev.map(p => p.id === postId ? { ...p, isHidden } : p));
  };

  const handleDelete = async (postId) => {
    if (!window.confirm('Are you sure you want to permanently delete this post? This action cannot be undone.')) return;
    await deleteDoc(doc(db, 'posts', postId));
    setPosts(prev => prev.filter(p => p.id !== postId));
    setSelectedPostId(prev => (prev === postId ? null : prev));
  };

  const handleSavePost = async (postId, changes) => {
    await updateDoc(doc(db, 'posts', postId), changes);
    setPosts(prev => prev.map(p => p.id === postId ? { ...p, ...changes } : p));
  };

  // Distinct post types actually present in the loaded data — no hardcoded list.
  const types = Array.from(new Set(posts.map(p => p.type).filter(Boolean))).sort();

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

  // All filtering happens locally against the posts already fetched above —
  // no additional Firestore reads are triggered by search or filter changes.
  const filtered = posts.filter(p => {
    const q = search.toLowerCase();
    const matchesSearch = !q ||
      (p.authorName || '').toLowerCase().includes(q) ||
      (p.foodName || '').toLowerCase().includes(q) ||
      (p.caption || '').toLowerCase().includes(q);
    const matchesType = typeFilter === 'all' || p.type === typeFilter;
    const isHidden = !!p.isHidden;
    const matchesStatus = statusFilter === 'all' ||
      (statusFilter === 'hidden' ? isHidden : !isHidden);
    return matchesSearch && matchesType && matchesStatus && matchesDateFilter(p);
  });

  const selectedPost = posts.find(p => p.id === selectedPostId) || null;

  // Exports exactly the rows currently matching search + filters. imageBase64
  // is deliberately excluded — it can be large and would bloat the file.
  const handleExport = () => {
    const rows = filtered.map(p => ({
      'Post ID': p.id,
      Author: p.authorName || '—',
      'User UID': p.uid || '—',
      'Food Name': p.foodName || '—',
      Caption: p.caption || '—',
      Type: p.type || '—',
      Calories: p.calories ?? '—',
      'Protein (g)': p.proteinG ?? '—',
      'Carbs (g)': p.carbsG ?? '—',
      'Fat (g)': p.fatG ?? '—',
      Reactions: p.reactionCount ?? 0,
      Comments: p.commentCount ?? 0,
      Status: p.isHidden ? 'Hidden' : 'Active',
      'Created Date': formatDate(p.createdAt),
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

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Posts"
        subtitle={loading ? 'Loading posts…' : `${posts.length} posts on the platform`}
      />

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <div className={selectedPost ? 'wwa-split-layout' : ''}>
          <div className={selectedPost ? 'wwa-split-main' : ''}>
            <div className="wwa-toolbar">
              <div className="wwa-search">
                <input
                  className="wwa-input"
                  placeholder="Search by author, food name, or caption…"
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                />
              </div>

              <select
                className="wwa-select wwa-select-inline"
                value={typeFilter}
                onChange={e => setTypeFilter(e.target.value)}
              >
                <option value="all">All Types</option>
                {types.map(t => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={statusFilter}
                onChange={e => setStatusFilter(e.target.value)}
              >
                <option value="all">Status: All</option>
                <option value="active">Status: Active</option>
                <option value="hidden">Status: Hidden</option>
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={dateFilter}
                onChange={e => setDateFilter(e.target.value)}
              >
                <option value="all">Date: All Time</option>
                <option value="today">Date: Today</option>
                <option value="7days">Date: Last 7 Days</option>
                <option value="30days">Date: Last 30 Days</option>
              </select>

              <button className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={resetFilters}>
                Reset Filters
              </button>

              <button
                className="wwa-btn wwa-btn-sm wwa-btn-success"
                onClick={handleExport}
                disabled={filtered.length === 0}
              >
                📤 Export to Excel
              </button>

              <span className="wwa-toolbar-count">{filtered.length} of {posts.length} posts</span>
            </div>

            <div className="wwa-table-wrap">
              <table className="wwa-table">
                <thead>
                  <tr>
                    {['Author', 'Post / Food Name', 'Type', 'Calories', 'Reactions', 'Comments', 'Status', 'Created Date', 'Action'].map(h => (
                      <th key={h}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map(post => {
                    const isHidden = !!post.isHidden;
                    return (
                      <tr key={post.id} className={selectedPostId === post.id ? 'wwa-row-selected' : ''}>
                        <td>
                          <div className="wwa-cell-primary">{post.authorName || '—'}</div>
                          <div className="wwa-cell-muted">{post.uid || '—'}</div>
                        </td>
                        <td>
                          <div className="wwa-cell-primary">{post.foodName || '—'}</div>
                          {post.caption && <div className="wwa-cell-muted">{post.caption}</div>}
                        </td>
                        <td>
                          <Badge tone="neutral">{post.type || '—'}</Badge>
                        </td>
                        <td>{post.calories ?? '—'}</td>
                        <td>{post.reactionCount ?? 0}</td>
                        <td>{post.commentCount ?? 0}</td>
                        <td>
                          <Badge tone={isHidden ? 'danger' : 'success'}>
                            {isHidden ? 'Hidden' : 'Active'}
                          </Badge>
                        </td>
                        <td style={{ color: '#6b7280' }}>{formatDate(post.createdAt)}</td>
                        <td>
                          <div className="wwa-cell-actions">
                            <button
                              className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                              onClick={() => setSelectedPostId(post.id)}
                            >
                              View
                            </button>
                            <button
                              className={`wwa-btn wwa-btn-sm ${isHidden ? 'wwa-btn-success-soft' : 'wwa-btn-secondary'}`}
                              onClick={() => toggleHidden(post.id, isHidden)}
                            >
                              {isHidden ? 'Unhide' : 'Hide'}
                            </button>
                            <button
                              className="wwa-btn wwa-btn-sm wwa-btn-danger"
                              onClick={() => handleDelete(post.id)}
                            >
                              Delete
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {filtered.length === 0 && (
                <EmptyState
                  icon="📝"
                  title="No posts found"
                  message={hasActiveFilters ? 'Try adjusting your search or filters.' : 'No posts on the platform yet.'}
                />
              )}
            </div>
          </div>

          {selectedPost && (
            <div className="wwa-split-side">
              <PostDetailPanel
                post={selectedPost}
                onClose={() => setSelectedPostId(null)}
                onSave={handleSavePost}
                onToggleHidden={toggleHidden}
                onDelete={handleDelete}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default Posts;
