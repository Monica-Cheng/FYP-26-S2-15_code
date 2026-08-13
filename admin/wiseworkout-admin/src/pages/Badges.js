import React, { useEffect, useMemo, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Eye, Pencil, Plus, Trash2 } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import ConditionsEditor from '../components/ConditionsEditor';
import BadgeDetailPanel from '../components/BadgeDetailPanel';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import DataTable from '../components/ui/DataTable';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import TableActions from '../components/ui/TableActions';
import ModalDialog from '../components/ui/ModalDialog';
import ImageThumb from '../components/ui/ImageThumb';
import useClientPagination from '../hooks/useClientPagination';
import { formatDate } from '../utils/dateUtils';
import {
  FALLBACK_BADGE_STAT_TYPES,
  formatConditionsSummary,
  normalizeConditionsForSave,
  validateBadgeForm,
  getBadgeCallableErrorMessage,
} from '../utils/badgeUtils';

const emptyForm = { name: '', description: '', imageUrl: '', conditions: [{ statType: '', value: '' }] };
const DELETE_CONFIRMATION = 'DELETE BADGE';

function BadgesStyles() {
  return (
    <style>{`
      .wwba-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwba-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwba-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
      }
      .wwba-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwba-form-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwba-table .wwa-table th:last-child,
      .wwba-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwba-badge-cell {
        min-width: 0;
      }
      .wwba-badge-cell__title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwba-badge-cell__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwba-condition {
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwba-badge-id {
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
      }
      .wwba-modal-copy {
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
      .wwba-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        white-space: nowrap;
      }
      @media (max-width: 1160px) {
        .wwba-layout.has-detail {
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

function Badges() {
  const [badges, setBadges] = useState([]);
  const [supportedStatTypes, setSupportedStatTypes] = useState(FALLBACK_BADGE_STAT_TYPES);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [search, setSearch] = useState('');
  const [selectedBadgeId, setSelectedBadgeId] = useState(null);
  const [openInEdit, setOpenInEdit] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);
  const [addForm, setAddForm] = useState(emptyForm);
  const [addSaving, setAddSaving] = useState(false);
  const [addError, setAddError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [deleteBadge, setDeleteBadge] = useState(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [deleteSaving, setDeleteSaving] = useState(false);
  const [deleteError, setDeleteError] = useState('');

  const fetchBadges = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminListBadgesDashboard = httpsCallable(functions, 'adminListBadgesDashboard');
      const result = await adminListBadgesDashboard();
      const data = result.data || {};
      setBadges(Array.isArray(data.badges) ? data.badges : []);
      setSupportedStatTypes(
        Array.isArray(data.supportedStatTypes) && data.supportedStatTypes.length > 0
          ? data.supportedStatTypes
          : FALLBACK_BADGE_STAT_TYPES
      );
    } catch (err) {
      console.error('Failed to load badges dashboard:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setLoadError(`Failed to load badges.${detail}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBadges();
  }, []);

  const handleAddBadge = async () => {
    const validationError = validateBadgeForm(addForm, supportedStatTypes);
    if (validationError) {
      setAddError(validationError);
      return;
    }

    setAddSaving(true);
    setAddError('');

    try {
      const payload = {
        name: addForm.name.trim(),
        description: addForm.description.trim(),
        imageUrl: addForm.imageUrl.trim(),
        conditions: normalizeConditionsForSave(addForm.conditions),
      };

      const adminCreateBadge = httpsCallable(functions, 'adminCreateBadge');
      const result = await adminCreateBadge({
        badge: payload,
      });

      setBadges((prev) => [
        ...prev,
        {
          id: result.data.badgeId,
          ...(result.data.badge || payload),
        },
      ]);

      setShowAddForm(false);
      setAddForm(emptyForm);
      setSuccessMsg('Badge added successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to add badge:', err);
      setAddError(getBadgeCallableErrorMessage(err, 'Failed to add badge. Please try again.'));
    } finally {
      setAddSaving(false);
    }
  };

  const handleSaveBadge = async (badgeId, changes) => {
    const adminUpdateBadge = httpsCallable(functions, 'adminUpdateBadge');
    const result = await adminUpdateBadge({
      badgeId,
      changes,
    });
    const savedBadge = result.data?.badge || changes;

    setBadges((prev) =>
      prev.map((badge) =>
        badge.id === badgeId
          ? { ...badge, ...savedBadge }
          : badge
      )
    );
  };

  const handleDeleteBadge = async () => {
    if (!deleteBadge) return;
    try {
      setDeleteSaving(true);
      setDeleteError('');
      const adminDeleteBadge = httpsCallable(functions, 'adminDeleteBadge');
      await adminDeleteBadge({
        badgeId: deleteBadge.id,
        confirmation: deleteConfirmation,
      });

      setBadges((prev) => prev.filter((item) => item.id !== deleteBadge.id));
      setSelectedBadgeId((prev) => (prev === deleteBadge.id ? null : prev));
      setDeleteBadge(null);
      setDeleteConfirmation('');
      setDeleteError('');
      setSuccessMsg('Badge deleted successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to delete badge:', err);
      setDeleteError(getBadgeCallableErrorMessage(err, 'Failed to delete badge. Please try again.'));
    } finally {
      setDeleteSaving(false);
    }
  };

  const openBadgeView = (badge) => {
    setShowAddForm(false);
    setAddError('');
    setSelectedBadgeId(badge.id);
    setOpenInEdit(false);
  };

  const openBadgeEdit = (badge) => {
    setShowAddForm(false);
    setAddError('');
    setSelectedBadgeId(badge.id);
    setOpenInEdit(true);
  };

  const openDeleteDialog = (badge) => {
    setDeleteBadge(badge);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const closeDeleteDialog = () => {
    if (deleteSaving) return;
    setDeleteBadge(null);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const filtered = useMemo(() => {
    return badges.filter((badge) => {
      const query = search.toLowerCase();
      if (!query) return true;

      const matchesBasic =
        (badge.name || '').toLowerCase().includes(query) ||
        (badge.id || '').toLowerCase().includes(query) ||
        (badge.description || '').toLowerCase().includes(query);
      const matchesStat =
        Array.isArray(badge.conditions) &&
        badge.conditions.some((condition) => (condition?.statType || '').toLowerCase().includes(query));

      return matchesBasic || matchesStat;
    });
  }, [badges, search]);

  const badgesPagination = useClientPagination(filtered, {
    resetKey: search,
  });

  const selectedBadge = badges.find((badge) => badge.id === selectedBadgeId) || null;

  const columns = [
    {
      key: 'badge',
      header: 'Badge',
      render: (badge) => (
        <div className="wwba-badge-cell">
          <div className="wwba-badge-cell__title">{badge.name || 'Unnamed badge'}</div>
        </div>
      ),
    },
    {
      key: 'badgeId',
      header: 'Badge ID',
      render: (badge) => (
        <div className="wwba-badge-id" title={badge.id || '—'}>
          {badge.id || '—'}
        </div>
      ),
    },
    {
      key: 'conditions',
      header: 'Conditions',
      render: (badge) => <span className="wwba-condition">{formatConditionsSummary(badge.conditions)}</span>,
    },
    {
      key: 'image',
      header: 'Image',
      render: (badge) => <ImageThumb url={badge.imageUrl} size={48} icon="🏅" />,
    },
    {
      key: 'updatedAt',
      header: 'Updated At',
      render: (badge) => formatDate(badge.updatedAt),
    },
  ];

  const openAddForm = () => {
    setSelectedBadgeId(null);
    setOpenInEdit(false);
    setShowAddForm(true);
    setAddError('');
    setAddForm(emptyForm);
  };

  return (
    <div className="wwba-page">
      <AdminStyles />
      <BadgesStyles />

      <PageHeader
        title="Badges"
        description="Manage achievement badges and earning conditions"
        count={loading ? undefined : `${badges.length} badges`}
        actions={
          !loading ? (
            <>
              {successMsg ? (
                <span className="wwa-status-pill">
                  <span className="wwa-status-dot" />
                  {successMsg}
                </span>
              ) : null}
              <button type="button" className="wwa-btn wwa-btn-primary" onClick={openAddForm}>
                <Plus aria-hidden="true" size={16} strokeWidth={2} />
                Add Badge
              </button>
            </>
          ) : null
        }
      />

      {loading ? (
        <LoadingState rows={6} />
      ) : loadError ? (
        <ErrorState title="Failed to load badges" message={loadError} onRetry={fetchBadges} />
      ) : (
        <>
          {showAddForm ? (
            <div className="wwa-panel wwba-form">
              <div>
                <div className="wwa-panel-title">New Badge</div>
                <div className="wwa-panel-subtitle">Fill in the badge details and its earning conditions.</div>
              </div>

              {addError ? <div className="wwa-alert-error">{addError}</div> : null}

              <FormSection title="Basic Information" columns={2}>
                <FormField label="Badge Name" labelFor="new-badge-name" required>
                  <input
                    id="new-badge-name"
                    className="wwa-input"
                    value={addForm.name}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, name: event.target.value }))}
                    placeholder="e.g. Distance Runner"
                    maxLength={100}
                  />
                </FormField>

                <FormField label="Image URL" labelFor="new-badge-image-url">
                  <input
                    id="new-badge-image-url"
                    className="wwa-input"
                    value={addForm.imageUrl}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, imageUrl: event.target.value }))}
                    placeholder="https://…"
                  />
                </FormField>

                <FormField label="Description" labelFor="new-badge-description" required fullWidth>
                  <input
                    id="new-badge-description"
                    className="wwa-input"
                    value={addForm.description}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, description: event.target.value }))}
                    placeholder="e.g. Run 50km total"
                    maxLength={500}
                  />
                </FormField>
              </FormSection>

              <FormSection title="Earning Conditions" columns={1}>
                <ConditionsEditor
                  conditions={addForm.conditions}
                  onChange={(next) => setAddForm((prev) => ({ ...prev, conditions: next }))}
                  disabled={addSaving}
                  supportedStatTypes={supportedStatTypes}
                />
              </FormSection>

              <div className="wwba-form-actions">
                <button
                  type="button"
                  className="wwa-btn wwa-btn-secondary"
                  onClick={() => {
                    setShowAddForm(false);
                    setAddError('');
                  }}
                  disabled={addSaving}
                >
                  Cancel
                </button>
                <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleAddBadge} disabled={addSaving}>
                  {addSaving ? 'Saving...' : 'Save Badge'}
                </button>
              </div>
            </div>
          ) : null}

          <div className={`wwba-layout ${selectedBadge ? 'has-detail' : ''}`}>
            <div>
              <FilterBar
                search={
                  <SearchInput
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    onClear={() => setSearch('')}
                    placeholder="Search by name, description, or stat type…"
                    label="Search badges"
                  />
                }
                count={`${filtered.length} of ${badges.length} badges`}
              />

              <DataTable
                className="wwba-table"
                columns={columns}
                rows={badgesPagination.paginatedItems}
                getRowKey={(badge) => badge.id}
                selectedRowKey={selectedBadgeId}
                onRowClick={(badge) => openBadgeView(badge)}
                minWidth={980}
                pagination={{
                  currentPage: badgesPagination.currentPage,
                  pageSize: badgesPagination.pageSize,
                  totalItems: badgesPagination.totalItems,
                  totalPages: badgesPagination.totalPages,
                  pageSizeOptions: badgesPagination.pageSizeOptions,
                  onPageChange: badgesPagination.setCurrentPage,
                  onPageSizeChange: badgesPagination.setPageSize,
                }}
                emptyIcon={null}
                emptyTitle="No badges found"
                emptyMessage={search ? 'Try a different search term.' : 'No badges added yet.'}
                renderRowActions={(badge) => (
                  <div className="wwba-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                      onClick={(event) => {
                        event.stopPropagation();
                        openBadgeView(badge);
                      }}
                      aria-label={`View ${badge.name || 'badge'}`}
                    >
                      <Eye aria-hidden="true" size={14} strokeWidth={2} />
                      View
                    </button>
                    <TableActions
                      label={`Actions for ${badge.name || 'badge'}`}
                      items={[
                        {
                          key: 'edit',
                          label: 'Edit',
                          icon: <Pencil aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openBadgeEdit(badge),
                        },
                        { type: 'divider' },
                        {
                          key: 'delete',
                          label: 'Delete',
                          tone: 'danger',
                          icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openDeleteDialog(badge),
                        },
                      ]}
                    />
                  </div>
                )}
              />
            </div>

            {selectedBadge ? (
              <BadgeDetailPanel
                badge={selectedBadge}
                startInEdit={openInEdit}
                onClose={() => setSelectedBadgeId(null)}
                onSave={handleSaveBadge}
                onEdit={openBadgeEdit}
                onDelete={openDeleteDialog}
                supportedStatTypes={supportedStatTypes}
              />
            ) : null}
          </div>
        </>
      )}

      <ModalDialog
        open={Boolean(deleteBadge)}
        title="Delete Badge"
        description="This permanently removes the badge definition. Badges that have already been earned cannot be deleted."
        onClose={closeDeleteDialog}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeDeleteDialog} disabled={deleteSaving}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={handleDeleteBadge}
              disabled={deleteSaving || deleteConfirmation !== DELETE_CONFIRMATION}
            >
              {deleteSaving ? 'Deleting...' : 'Delete Badge'}
            </button>
          </>
        }
      >
        <div className="wwba-modal-copy">
          Delete <strong>"{deleteBadge?.name || 'this badge'}"</strong>?
        </div>
        <FormSection columns={1}>
          <FormField label="Confirmation" labelFor="badge-delete-confirmation" required fullWidth>
            <input
              id="badge-delete-confirmation"
              type="text"
              className="wwa-input"
              value={deleteConfirmation}
              onChange={(event) => setDeleteConfirmation(event.target.value)}
              placeholder={DELETE_CONFIRMATION}
            />
          </FormField>
        </FormSection>
        {deleteError ? <div className="wwa-alert-error">{deleteError}</div> : null}
      </ModalDialog>
    </div>
  );
}

export default Badges;
