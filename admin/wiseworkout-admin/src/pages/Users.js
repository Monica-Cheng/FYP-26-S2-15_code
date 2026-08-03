import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, doc, updateDoc, deleteDoc } from 'firebase/firestore';
import * as XLSX from 'xlsx';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import UserDetailPanel from '../components/UserDetailPanel';

function Users() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [levelFilter, setLevelFilter] = useState('all');
  const [onboardedFilter, setOnboardedFilter] = useState('all');
  const [healthFilter, setHealthFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [premiumFilter, setPremiumFilter] = useState('all');
  const [selectedUserId, setSelectedUserId] = useState(null);

  const [loadError, setLoadError] = useState('');

  useEffect(() => {
    const fetchUsers = async () => {
      setLoadError('');
      try {
        const snap = await getDocs(collection(db, 'users'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setUsers(data);
      } catch (err) {
        console.error(err);
        const detail = err && err.code ? ` (${err.code})` : '';
        setLoadError(`Failed to load users.${detail}`);
      }
      setLoading(false);
    };
    fetchUsers();
  }, []);

  const toggleSuspend = async (userId, currentStatus) => {
    const newStatus = currentStatus === 'suspended' ? 'active' : 'suspended';
    await updateDoc(doc(db, 'users', userId), { accountStatus: newStatus });
    setUsers(prev => prev.map(u => u.id === userId ? { ...u, accountStatus: newStatus } : u));
  };
  const handleDelete = async (userId) => {
    if (!window.confirm('Permanently delete this user? This cannot be undone.')) return;
    await deleteDoc(doc(db, 'users', userId));
    setUsers(prev => prev.filter(u => u.id !== userId));
    setSelectedUserId(prev => (prev === userId ? null : prev));
  };

  // Writes only the changed fields (partial update — Firestore leaves every
  // other field on the document untouched) and mirrors the change into local
  // state so the table and detail panel reflect it immediately.
  const handleSaveUser = async (userId, changes) => {
    await updateDoc(doc(db, 'users', userId), changes);
    setUsers(prev => prev.map(u => u.id === userId ? { ...u, ...changes } : u));
  };

  // Distinct levels actually present in the loaded data — no hardcoded list.
  const levels = Array.from(new Set(users.map(u => u.level || 1))).sort((a, b) => a - b);

  const hasActiveFilters = Boolean(
    search || levelFilter !== 'all' || onboardedFilter !== 'all' ||
    healthFilter !== 'all' || statusFilter !== 'all' || premiumFilter !== 'all'
  );

  const resetFilters = () => {
    setSearch('');
    setLevelFilter('all');
    setOnboardedFilter('all');
    setHealthFilter('all');
    setStatusFilter('all');
    setPremiumFilter('all');
  };

  // All filtering happens locally against the users already fetched above —
  // no additional Firestore reads are triggered by search or filter changes.
  const filtered = users.filter(u => {
    const q = search.toLowerCase();
    const matchesSearch =
      (u.displayName || '').toLowerCase().includes(q) ||
      (u.username || '').toLowerCase().includes(q) ||
      (u.email || '').toLowerCase().includes(q) ||
      (u.id || '').toLowerCase().includes(q);
    const matchesLevel = levelFilter === 'all' || (u.level || 1) === Number(levelFilter);
    const matchesOnboarded = onboardedFilter === 'all' ||
      (onboardedFilter === 'yes' ? !!u.onboardingComplete : !u.onboardingComplete);
    const matchesHealth = healthFilter === 'all' ||
      (healthFilter === 'connected' ? !!u.healthConnected : !u.healthConnected);
    const matchesStatus = statusFilter === 'all' ||
      (statusFilter === 'suspended' ? u.accountStatus === 'suspended' : u.accountStatus !== 'suspended');
    const matchesPremium = premiumFilter === 'all' ||
      (premiumFilter === 'premium' ? !!u.isPremium : !u.isPremium);
    return matchesSearch && matchesLevel && matchesOnboarded && matchesHealth && matchesStatus && matchesPremium;
  });

  const selectedUser = users.find(u => u.id === selectedUserId) || null;

  // Exports exactly the table's visible columns, for exactly the rows
  // currently matching search + filters — no hidden fields (id/email/XP/
  // subscription/goal) are included.
  const handleExport = () => {
    const rows = filtered.map(u => ({
      'Display Name': u.displayName || '—',
      Username: u.username || '—',
      'User ID': u.id,
      Level: `Level ${u.level || 1}`,
      Onboarded: u.onboardingComplete ? 'Yes' : 'No',
      'Health Connected': u.healthConnected ? 'Connected' : 'Not Connected',
      'Wearable Connected': u.wearableConnected ? 'Connected' : 'Not Connected',
      'Premium Status': u.isPremium ? 'Premium' : 'Free',
      Status: u.accountStatus === 'suspended' ? 'Suspended' : 'Active',
      'Primary Goal': u.planMatchGoal || '—',
      Hometown: u.hometown || '—',
      'Total XP': u.totalXp ?? 0,
      'Weekly XP': u.weeklyXp ?? 0,
      'Tracked Plan': u.trackedPlanName || '—',
      'Saved Plans Count': Array.isArray(u.savedPlanIds) ? u.savedPlanIds.length : 0,
    }));
    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 22 }, { wch: 18 }, { wch: 24 }, { wch: 9 }, { wch: 10 },
      { wch: 16 }, { wch: 17 }, { wch: 14 }, { wch: 11 }, { wch: 18 },
      { wch: 16 }, { wch: 10 }, { wch: 10 }, { wch: 22 }, { wch: 16 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Users');

    const now = new Date();
    const dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    XLSX.writeFile(workbook, `WiseWorkout_Users_${dateStr}.xlsx`);
  };

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Users"
        subtitle={loading ? 'Loading users…' : `${users.length} registered accounts`}
      />

      {!loading && loadError && (
        <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{loadError}</div>
      )}

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <div className={selectedUser ? 'wwa-split-layout' : ''}>
          <div className={selectedUser ? 'wwa-split-main' : ''}>
            <div className="wwa-toolbar">
              <div className="wwa-search">
                <input
                  className="wwa-input"
                  placeholder="Search by name, username, or ID…"
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                />
              </div>

              <select
                className="wwa-select wwa-select-inline"
                value={levelFilter}
                onChange={e => setLevelFilter(e.target.value)}
              >
                <option value="all">All Levels</option>
                {levels.map(l => (
                  <option key={l} value={l}>Level {l}</option>
                ))}
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={onboardedFilter}
                onChange={e => setOnboardedFilter(e.target.value)}
              >
                <option value="all">Onboarded: All</option>
                <option value="yes">Onboarded: Yes</option>
                <option value="no">Onboarded: No</option>
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={healthFilter}
                onChange={e => setHealthFilter(e.target.value)}
              >
                <option value="all">Health: All</option>
                <option value="connected">Health: Connected</option>
                <option value="not">Health: Not Connected</option>
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={statusFilter}
                onChange={e => setStatusFilter(e.target.value)}
              >
                <option value="all">Status: All</option>
                <option value="active">Status: Active</option>
                <option value="suspended">Status: Suspended</option>
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={premiumFilter}
                onChange={e => setPremiumFilter(e.target.value)}
              >
                <option value="all">Premium Status: All</option>
                <option value="premium">Premium Status: Premium</option>
                <option value="free">Premium Status: Free</option>
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

              <span className="wwa-toolbar-count">{filtered.length} of {users.length} users</span>
            </div>

            <div className="wwa-table-wrap">
              <table className="wwa-table">
                <thead>
                  <tr>
                    {['Name', 'Level', 'Onboarded', 'Health Connected', 'Premium Status', 'Status', 'Action'].map(h => (
                      <th key={h}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map(user => (
                    <tr key={user.id} className={selectedUserId === user.id ? 'wwa-row-selected' : ''}>
                      <td>
                        <div className="wwa-cell-primary">
                          {user.displayName || user.username || 'Unnamed User'}
                        </div>
                        <div className="wwa-cell-muted">{user.id}</div>
                      </td>
                      <td>
                        <Badge tone="neutral">Level {user.level || 1}</Badge>
                      </td>
                      <td>
                        <Badge tone={user.onboardingComplete ? 'success' : 'danger'}>
                          {user.onboardingComplete ? 'Yes' : 'No'}
                        </Badge>
                      </td>
                      <td>
                        <Badge tone={user.healthConnected ? 'success' : 'neutral'}>
                          {user.healthConnected ? 'Connected' : 'Not connected'}
                        </Badge>
                      </td>
                      <td>
                        <Badge tone={user.isPremium ? 'brand' : 'neutral'}>
                          {user.isPremium ? 'Premium' : 'Free'}
                        </Badge>
                      </td>
                      <td>
                        <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
                          {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
                        </Badge>
                      </td>
                      <td>
                        <div className="wwa-cell-actions">
                          <button
                            className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                            onClick={() => setSelectedUserId(user.id)}
                          >
                            View
                          </button>
                          <button
                            className={`wwa-btn wwa-btn-sm ${user.accountStatus === 'suspended' ? 'wwa-btn-success-soft' : 'wwa-btn-danger'}`}
                            onClick={() => toggleSuspend(user.id, user.accountStatus)}
                          >
                            {user.accountStatus === 'suspended' ? 'Reinstate' : 'Suspend'}
                          </button>
                          <button
                            className="wwa-btn wwa-btn-sm wwa-btn-danger"
                            onClick={() => handleDelete(user.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {filtered.length === 0 && (
                <EmptyState
                  icon="👥"
                  title="No users found"
                  message={hasActiveFilters ? 'Try adjusting your search or filters.' : 'No registered accounts yet.'}
                />
              )}
            </div>
          </div>

          {selectedUser && (
            <div className="wwa-split-side">
              <UserDetailPanel
                user={selectedUser}
                onClose={() => setSelectedUserId(null)}
                onSave={handleSaveUser}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default Users;
