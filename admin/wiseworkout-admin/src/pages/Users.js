import React, { useEffect, useMemo, useState } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import { Download, ShieldOff, ShieldCheck, Trash2 } from 'lucide-react';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import UserDetailPanel from '../components/UserDetailPanel';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import SelectField from '../components/ui/SelectField';
import DataTable from '../components/ui/DataTable';
import TableActions from '../components/ui/TableActions';
import ModalDialog from '../components/ui/ModalDialog';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import useClientPagination from '../hooks/useClientPagination';
import { formatDate } from '../utils/dateUtils';

const exportValue = (value) => {
  if (value === undefined || value === null || value === '') return '—';
  return value;
};

const exportYesNo = (value) => (value ? 'Yes' : 'No');

const flattenEquipment = (value) => {
  if (Array.isArray(value)) {
    const items = value.map((item) => (item || '').trim()).filter(Boolean);
    return items.length > 0 ? items.join(', ') : '—';
  }
  if (typeof value === 'string' && value.trim()) return value.trim();
  return '—';
};

function UsersStyles() {
  return (
    <style>{`
      .wwus-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwus-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwus-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) minmax(360px, var(--ww-drawer-width));
        align-items: start;
      }
      .wwus-user-cell {
        min-width: 0;
      }
      .wwus-user-cell__name {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
        line-height: 1.35;
      }
      .wwus-user-cell__meta {
        margin-top: 3px;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwus-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        white-space: nowrap;
      }
      .wwus-table .wwa-table th:last-child,
      .wwus-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwus-modal-copy {
        color: var(--ww-text-sec);
        line-height: 1.5;
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
      @media (max-width: 1240px) {
        .wwus-layout.has-detail {
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

const DELETE_CONFIRMATION = 'DELETE';

const emptyActionState = {
  type: null,
  user: null,
  deleteConfirmation: '',
  uidConfirmation: '',
  error: '',
  saving: false,
};

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
  const [actionState, setActionState] = useState(emptyActionState);

  const fetchUsers = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminListUsers = httpsCallable(functions, 'adminListUsers');
      const result = await adminListUsers();
      setUsers(Array.isArray(result.data.users) ? result.data.users : []);
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      setLoadError(`Failed to load users.${detail}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchUsers();
  }, []);

  const updateUserStatus = async (userId, currentStatus) => {
    const suspended = currentStatus !== 'suspended';
    try {
      const adminSetUserSuspended = httpsCallable(functions, 'adminSetUserSuspended');
      const result = await adminSetUserSuspended({
        uid: userId,
        suspended,
      });

      const newStatus = result.data.accountStatus;

      setUsers((prev) =>
        prev.map((user) =>
          user.id === userId
            ? { ...user, accountStatus: newStatus }
            : user
        )
      );
    } catch (err) {
      console.error(err);
      throw new Error(err.message || 'Failed to update the user account status.');
    }
  };

  const deleteUser = async (user, uidConfirmation) => {
    const userLabel = user.displayName || user.username || user.email || user.id;

    try {
      const adminDeleteUser = httpsCallable(functions, 'adminDeleteUser');

      await adminDeleteUser({
        uid: user.id,
        confirmUid: uidConfirmation,
      });

      setUsers((prev) => prev.filter((existingUser) => existingUser.id !== user.id));
      setSelectedUserId((prev) => (prev === user.id ? null : prev));
      return `"${userLabel}" was permanently deleted successfully.`;
    } catch (err) {
      console.error(err);
      throw new Error(err.message || 'The user could not be permanently deleted.');
    }
  };

  const handleSaveUser = async (userId, changes) => {
    try {
      const adminUpdateUser = httpsCallable(functions, 'adminUpdateUser');
      const result = await adminUpdateUser({
        uid: userId,
        changes,
      });

      const savedChanges = result.data.changes || changes;

      setUsers((prev) =>
        prev.map((user) =>
          user.id === userId
            ? { ...user, ...savedChanges }
            : user
        )
      );
    } catch (err) {
      console.error(err);
      throw err;
    }
  };

  const levels = Array.from(new Set(users.map((user) => user.level || 1))).sort((a, b) => a - b);

  const hasActiveFilters = Boolean(
    search ||
    levelFilter !== 'all' ||
    onboardedFilter !== 'all' ||
    healthFilter !== 'all' ||
    statusFilter !== 'all' ||
    premiumFilter !== 'all'
  );

  const resetFilters = () => {
    setSearch('');
    setLevelFilter('all');
    setOnboardedFilter('all');
    setHealthFilter('all');
    setStatusFilter('all');
    setPremiumFilter('all');
  };

  const filtered = useMemo(() => {
    return users.filter((user) => {
      const q = search.toLowerCase();
      const matchesSearch =
        (user.displayName || '').toLowerCase().includes(q) ||
        (user.username || '').toLowerCase().includes(q) ||
        (user.email || '').toLowerCase().includes(q) ||
        (user.id || '').toLowerCase().includes(q);
      const matchesLevel = levelFilter === 'all' || (user.level || 1) === Number(levelFilter);
      const matchesOnboarded =
        onboardedFilter === 'all' ||
        (onboardedFilter === 'yes' ? !!user.onboardingComplete : !user.onboardingComplete);
      const matchesHealth =
        healthFilter === 'all' ||
        (healthFilter === 'connected' ? !!user.healthConnected : !user.healthConnected);
      const matchesStatus =
        statusFilter === 'all' ||
        (statusFilter === 'suspended' ? user.accountStatus === 'suspended' : user.accountStatus !== 'suspended');
      const matchesPremium =
        premiumFilter === 'all' ||
        (premiumFilter === 'premium' ? !!user.isPremium : !user.isPremium);

      return matchesSearch && matchesLevel && matchesOnboarded && matchesHealth && matchesStatus && matchesPremium;
    });
  }, [users, search, levelFilter, onboardedFilter, healthFilter, statusFilter, premiumFilter]);

  const usersPagination = useClientPagination(filtered, {
    resetKey: [search, levelFilter, onboardedFilter, healthFilter, statusFilter, premiumFilter].join('|'),
  });

  const selectedUser = users.find((user) => user.id === selectedUserId) || null;

  const openUserView = (user) => {
    setSelectedUserId(user.id);
  };

  const openActionModal = (type, user) => {
    setActionState({
      type,
      user,
      deleteConfirmation: '',
      uidConfirmation: '',
      error: '',
      saving: false,
    });
  };

  const closeActionModal = () => {
    if (actionState.saving) return;
    setActionState(emptyActionState);
  };

  const submitActionModal = async () => {
    const { type, user } = actionState;
    if (!type || !user) return;

    setActionState((prev) => ({ ...prev, saving: true, error: '' }));

    try {
      if (type === 'suspend' || type === 'reactivate') {
        await updateUserStatus(user.id, user.accountStatus);
      } else if (type === 'delete') {
        await deleteUser(user, actionState.uidConfirmation);
        setActionState(emptyActionState);
        return;
      }

      setActionState(emptyActionState);
    } catch (err) {
      setActionState((prev) => ({
        ...prev,
        saving: false,
        error: err?.message || 'Action failed. Please try again.',
      }));
    }
  };

  const handleExport = () => {
    const includeCreatedAt = users.some((user) => user.createdAt);
    const includeUpdatedAt = users.some((user) => user.updatedAt);

    const rows = filtered.map((user) => {
      const row = {
        'User ID': exportValue(user.id),
        'Display Name': exportValue(user.displayName),
        Username: exportValue(user.username),
        Email: exportValue(user.email),
        Status: user.accountStatus === 'suspended' ? 'Suspended' : 'Active',
        'Premium Status': user.isPremium ? 'Premium' : 'Free',
        Level: user.level ?? 1,
        'Total XP': user.totalXp ?? 0,
        'Weekly XP': user.weeklyXp ?? 0,
        Onboarded: exportYesNo(!!user.onboardingComplete),
        'Health Connected': exportYesNo(!!user.healthConnected),
        'Wearable Connected': exportYesNo(!!user.wearableConnected),
        'Primary Goal': exportValue(user.planMatchGoal),
        'Plan Match Level': exportValue(user.planMatchLevel),
        'Plan Match Sport': exportValue(user.planMatchSport),
        'Plan Match Days': exportValue(user.planMatchDays),
        'Plan Match Equipment': flattenEquipment(user.planMatchEquipment),
        'Tracked Plan': exportValue(user.trackedPlanName),
        'Tracked Plan ID': exportValue(user.trackedPlanId),
        'Saved Plans Count': Array.isArray(user.savedPlanIds) ? user.savedPlanIds.length : 0,
        Hometown: exportValue(user.hometown),
        Bio: exportValue(user.bio),
      };

      if (includeCreatedAt) {
        row['Created At'] = user.createdAt ? formatDate(user.createdAt) : '—';
      }
      if (includeUpdatedAt) {
        row['Updated At'] = user.updatedAt ? formatDate(user.updatedAt) : '—';
      }

      return row;
    });

    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 24 }, { wch: 22 }, { wch: 18 }, { wch: 28 }, { wch: 12 },
      { wch: 14 }, { wch: 10 }, { wch: 12 }, { wch: 12 }, { wch: 12 },
      { wch: 18 }, { wch: 20 }, { wch: 18 }, { wch: 18 }, { wch: 18 },
      { wch: 16 }, { wch: 24 }, { wch: 22 }, { wch: 24 }, { wch: 16 },
      { wch: 18 }, { wch: 32 },
      ...(includeCreatedAt ? [{ wch: 20 }] : []),
      ...(includeUpdatedAt ? [{ wch: 20 }] : []),
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Users');

    const now = new Date();
    const dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    XLSX.writeFile(workbook, `WiseWorkout_Users_${dateStr}.xlsx`);
  };

  const columns = [
    {
      key: 'user',
      header: 'User',
      render: (user) => (
        <div className="wwus-user-cell">
          <div className="wwus-user-cell__name">{user.displayName || user.username || 'Unnamed User'}</div>
          <div className="wwus-user-cell__meta">{user.id}</div>
        </div>
      ),
    },
    {
      key: 'level',
      header: 'Level',
      render: (user) => <Badge tone="neutral">Level {user.level || 1}</Badge>,
    },
    {
      key: 'health',
      header: 'Health',
      render: (user) => (
        <Badge tone={user.healthConnected ? 'success' : 'neutral'}>
          {user.healthConnected ? 'Connected' : 'Not connected'}
        </Badge>
      ),
    },
    {
      key: 'subscription',
      header: 'Subscription',
      render: (user) => (
        <Badge tone={user.isPremium ? 'brand' : 'neutral'}>
          {user.isPremium ? 'Premium' : 'Free'}
        </Badge>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (user) => (
        <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
          {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
        </Badge>
      ),
    },
  ];

  return (
    <div className="wwus-page">
      <AdminStyles />
      <UsersStyles />

      <PageHeader
        title="Users"
        subtitle={loading ? 'Loading users…' : `${users.length} registered accounts`}
        actions={
          !loading ? (
            <button
              type="button"
              className="wwa-btn wwa-btn-secondary"
              onClick={handleExport}
              disabled={filtered.length === 0}
            >
              <Download aria-hidden="true" size={16} strokeWidth={2} />
              Export to Excel
            </button>
          ) : null
        }
      />

      {loading ? (
        <LoadingState rows={8} />
      ) : loadError ? (
        <ErrorState title="Failed to load users" message={loadError} onRetry={fetchUsers} />
      ) : (
        <div className={`wwus-layout ${selectedUser ? 'has-detail' : ''}`}>
          <div>
            <FilterBar
              search={
                <SearchInput
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  onClear={() => setSearch('')}
                  placeholder="Search by name, username, or ID…"
                  label="Search users"
                />
              }
              filters={
                <>
                  <SelectField
                    value={levelFilter}
                    onChange={(event) => setLevelFilter(event.target.value)}
                    options={[{ value: 'all', label: 'Level: All' }, ...levels.map((level) => ({ value: String(level), label: `Level ${level}` }))]}
                    aria-label="Filter users by level"
                  />
                  <SelectField
                    value={onboardedFilter}
                    onChange={(event) => setOnboardedFilter(event.target.value)}
                    options={[
                      { value: 'all', label: 'Onboarded: All' },
                      { value: 'yes', label: 'Onboarded: Yes' },
                      { value: 'no', label: 'Onboarded: No' },
                    ]}
                    aria-label="Filter users by onboarding status"
                  />
                  <SelectField
                    value={healthFilter}
                    onChange={(event) => setHealthFilter(event.target.value)}
                    options={[
                      { value: 'all', label: 'Health: All' },
                      { value: 'connected', label: 'Health: Connected' },
                      { value: 'not', label: 'Health: Not Connected' },
                    ]}
                    aria-label="Filter users by health connection"
                  />
                  <SelectField
                    value={statusFilter}
                    onChange={(event) => setStatusFilter(event.target.value)}
                    options={[
                      { value: 'all', label: 'Status: All' },
                      { value: 'active', label: 'Status: Active' },
                      { value: 'suspended', label: 'Status: Suspended' },
                    ]}
                    aria-label="Filter users by account status"
                  />
                  <SelectField
                    value={premiumFilter}
                    onChange={(event) => setPremiumFilter(event.target.value)}
                    options={[
                      { value: 'all', label: 'Premium: All' },
                      { value: 'premium', label: 'Premium: Premium' },
                      { value: 'free', label: 'Premium: Free' },
                    ]}
                    aria-label="Filter users by premium status"
                  />
                </>
              }
              onReset={resetFilters}
              resetLabel="Reset filters"
              resetVariant="secondary"
              resetDisabled={!hasActiveFilters}
              count={`${filtered.length} of ${users.length} users`}
            />

            <DataTable
              className="wwus-table"
              columns={columns}
              rows={usersPagination.paginatedItems}
              getRowKey={(user) => user.id}
              selectedRowKey={selectedUserId}
              onRowClick={(user) => openUserView(user)}
              minWidth={920}
              pagination={{
                currentPage: usersPagination.currentPage,
                pageSize: usersPagination.pageSize,
                totalItems: usersPagination.totalItems,
                totalPages: usersPagination.totalPages,
                pageSizeOptions: usersPagination.pageSizeOptions,
                onPageChange: usersPagination.setCurrentPage,
                onPageSizeChange: usersPagination.setPageSize,
              }}
              emptyTitle="No users found"
              emptyMessage={hasActiveFilters ? 'Try adjusting your search or filters.' : 'No registered accounts yet.'}
              emptyIcon={null}
              renderRowActions={(user) => (
                <div className="wwus-actions">
                  <button
                    type="button"
                    className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                    onClick={(event) => {
                      event.stopPropagation();
                      openUserView(user);
                    }}
                  >
                    View
                  </button>
                  <TableActions
                    label={`Actions for ${user.displayName || user.username || user.email || 'user'}`}
                    items={[
                      {
                        key: user.accountStatus === 'suspended' ? 'reactivate' : 'suspend',
                        label: user.accountStatus === 'suspended' ? 'Reinstate' : 'Suspend',
                        icon:
                          user.accountStatus === 'suspended' ? (
                            <ShieldCheck aria-hidden="true" size={14} strokeWidth={2} />
                          ) : (
                            <ShieldOff aria-hidden="true" size={14} strokeWidth={2} />
                          ),
                        onSelect: () => openActionModal(user.accountStatus === 'suspended' ? 'reactivate' : 'suspend', user),
                      },
                      { type: 'divider' },
                      {
                        key: 'delete',
                        label: 'Delete',
                        tone: 'danger',
                        icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                        onSelect: () => openActionModal('delete', user),
                      },
                    ]}
                  />
                </div>
              )}
            />
          </div>

          {selectedUser ? (
            <UserDetailPanel
              user={selectedUser}
              onClose={() => setSelectedUserId(null)}
              onSave={handleSaveUser}
              onSuspend={() => openActionModal('suspend', selectedUser)}
              onReactivate={() => openActionModal('reactivate', selectedUser)}
              onDelete={() => openActionModal('delete', selectedUser)}
            />
          ) : null}
        </div>
      )}

      <ModalDialog
        open={Boolean(actionState.type && actionState.user)}
        title={
          actionState.type === 'suspend'
            ? 'Suspend User'
            : actionState.type === 'reactivate'
              ? 'Reactivate User'
              : actionState.type === 'delete'
                ? 'Delete User'
                : 'User Action'
        }
        description={
          actionState.type === 'suspend'
            ? 'This updates the account status to suspended.'
            : actionState.type === 'reactivate'
              ? 'This restores the account to active status.'
              : actionState.type === 'delete'
                ? 'This permanently removes the Firebase Authentication account and related WiseWorkout data. This cannot be undone.'
                : undefined
        }
        onClose={closeActionModal}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeActionModal} disabled={actionState.saving}>
              Cancel
            </button>
            <button
              type="button"
              className={`wwa-btn ${actionState.type === 'delete' || actionState.type === 'suspend' ? 'wwa-btn-danger' : 'wwa-btn-primary'}`}
              onClick={submitActionModal}
              disabled={
                actionState.saving ||
                (actionState.type === 'delete' &&
                  (actionState.deleteConfirmation !== DELETE_CONFIRMATION || actionState.uidConfirmation !== actionState.user?.id))
              }
            >
              {actionState.saving
                ? actionState.type === 'delete'
                  ? 'Deleting...'
                  : actionState.type === 'reactivate'
                    ? 'Reactivating...'
                    : 'Suspending...'
                : actionState.type === 'delete'
                  ? 'Delete User'
                  : actionState.type === 'reactivate'
                    ? 'Reactivate User'
                    : 'Suspend User'}
            </button>
          </>
        }
      >
        {actionState.user ? (
          <>
            <div className="wwus-modal-copy">
              {actionState.type === 'delete' ? (
                <>
                  Delete <strong>"{actionState.user.displayName || actionState.user.username || actionState.user.email || actionState.user.id}"</strong>?
                </>
              ) : (
                <>
                  {actionState.type === 'reactivate' ? 'Reactivate' : 'Suspend'}{' '}
                  <strong>{actionState.user.displayName || actionState.user.username || actionState.user.email || actionState.user.id}</strong>
                  {actionState.user.email ? ` (${actionState.user.email})` : ''}?
                </>
              )}
            </div>
            {actionState.type === 'delete' ? (
              <FormSection columns={1}>
                <FormField label="Confirmation" labelFor="user-delete-confirmation" required fullWidth>
                  <input
                    id="user-delete-confirmation"
                    type="text"
                    className="wwa-input"
                    value={actionState.deleteConfirmation}
                    onChange={(event) => setActionState((prev) => ({ ...prev, deleteConfirmation: event.target.value }))}
                    placeholder={DELETE_CONFIRMATION}
                  />
                </FormField>
                <FormField label="User UID" labelFor="user-delete-uid" required fullWidth>
                  <input
                    id="user-delete-uid"
                    type="text"
                    className="wwa-input"
                    value={actionState.uidConfirmation}
                    onChange={(event) => setActionState((prev) => ({ ...prev, uidConfirmation: event.target.value }))}
                    placeholder={actionState.user.id}
                  />
                </FormField>
              </FormSection>
            ) : null}
            {actionState.error ? <div className="wwa-alert-error">{actionState.error}</div> : null}
          </>
        ) : null}
      </ModalDialog>
    </div>
  );
}

export default Users;
