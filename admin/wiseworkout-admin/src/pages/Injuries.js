import React, { useEffect, useMemo, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Eye, Pencil, Plus, Trash2 } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import InjuryDetailPanel from '../components/InjuryDetailPanel';
import DataTable from '../components/ui/DataTable';
import TableActions from '../components/ui/TableActions';
import ModalDialog from '../components/ui/ModalDialog';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import useClientPagination from '../hooks/useClientPagination';
import { getCallableErrorMessage } from '../utils/planUtils';

const emptyForm = { name: '', bodyPart: '', description: '' };
const DELETE_CONFIRMATION = 'DELETE INJURY';

function validateCategoryForm(form) {
  const name = (form.name || '').trim();
  const bodyPart = (form.bodyPart || '').trim();
  const description = (form.description || '').trim();

  if (!name) return 'Name is required.';
  if (!bodyPart) return 'Body Part is required.';
  if (!description) return 'Description is required.';
  if (name.length > 100) return 'Name cannot exceed 100 characters.';
  if (bodyPart.length > 100) return 'Body Part cannot exceed 100 characters.';
  if (description.length > 500) return 'Description cannot exceed 500 characters.';
  return '';
}

function InjuriesStyles() {
  return (
    <style>{`
      .wwin-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwin-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwin-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
      }
      .wwin-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwin-form-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwin-table .wwa-table th:last-child,
      .wwin-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwin-name {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwin-body-part,
      .wwin-description {
        color: var(--ww-text-sec);
      }
      .wwin-description {
        line-height: 1.45;
      }
      .wwin-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        white-space: nowrap;
      }
      .wwin-modal-copy {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwin-modal-copy strong {
        color: var(--ww-primary-dark);
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
      @media (max-width: 1120px) {
        .wwin-layout.has-detail {
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

function Injuries() {
  const [injuries, setInjuries] = useState([]);
  const [exercises, setExercises] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [search, setSearch] = useState('');
  const [selectedInjuryId, setSelectedInjuryId] = useState(null);
  const [openInEdit, setOpenInEdit] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);
  const [addForm, setAddForm] = useState(emptyForm);
  const [addSaving, setAddSaving] = useState(false);
  const [addError, setAddError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [deleteState, setDeleteState] = useState({ open: false, injuryId: null, blocked: false, usageCount: 0 });
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [deleteError, setDeleteError] = useState('');
  const [deleteSaving, setDeleteSaving] = useState(false);

  const fetchData = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminListInjuriesDashboard = httpsCallable(functions, 'adminListInjuriesDashboard');
      const result = await adminListInjuriesDashboard();
      const data = result.data || {};
      setInjuries(Array.isArray(data.injuries) ? data.injuries : []);
      setExercises(Array.isArray(data.exercises) ? data.exercises : []);
    } catch (err) {
      console.error('Failed to load injuries dashboard:', err);
      setLoadError(getCallableErrorMessage(err, 'Failed to load injuries dashboard.'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const countExercisesUsingInjury = (injuryName) => {
    const lower = (injuryName || '').trim().toLowerCase();
    return exercises.filter((exercise) =>
      Array.isArray(exercise.injuryRisk) &&
      exercise.injuryRisk.some((risk) => (risk || '').trim().toLowerCase() === lower)
    ).length;
  };

  const openDeleteDialog = (injury) => {
    const usageCount = countExercisesUsingInjury(injury.name);
    setDeleteState({
      open: true,
      injuryId: injury.id,
      blocked: usageCount > 0,
      usageCount,
    });
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const closeDeleteDialog = () => {
    if (deleteSaving) return;
    setDeleteState({ open: false, injuryId: null, blocked: false, usageCount: 0 });
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const openView = (injury, edit = false) => {
    setShowAddForm(false);
    setAddError('');
    setSelectedInjuryId(injury.id);
    setOpenInEdit(edit);
  };

  const openEdit = (injury) => openView(injury, true);

  const handleAddInjury = async () => {
    const validationError = validateCategoryForm(addForm);
    if (validationError) {
      setAddError(validationError);
      return;
    }

    setAddSaving(true);
    setAddError('');

    try {
      const payload = {
        name: addForm.name.trim(),
        bodyPart: addForm.bodyPart.trim(),
        description: addForm.description.trim(),
      };

      const adminCreateInjuryCategory = httpsCallable(functions, 'adminCreateInjuryCategory');
      const result = await adminCreateInjuryCategory({
        category: payload,
      });

      setInjuries((prev) => [
        ...prev,
        {
          id: result.data.categoryId,
          ...(result.data.category || payload),
        },
      ]);

      setShowAddForm(false);
      setAddForm(emptyForm);
      setSuccessMsg('Injury category added successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to add injury category:', err);
      setAddError(getCallableErrorMessage(err, 'Failed to add injury category. Please try again.'));
    } finally {
      setAddSaving(false);
    }
  };

  const handleSaveInjury = async (injuryId, changes) => {
    const adminUpdateInjuryCategory = httpsCallable(functions, 'adminUpdateInjuryCategory');
    const result = await adminUpdateInjuryCategory({
      categoryId: injuryId,
      changes,
    });
    const savedCategory = result.data?.category || changes;

    setInjuries((prev) =>
      prev.map((injury) =>
        injury.id === injuryId
          ? { ...injury, ...savedCategory }
          : injury
      )
    );
  };

  const handleDeleteInjury = async () => {
    const injury = injuries.find((item) => item.id === deleteState.injuryId);
    if (!injury || deleteState.blocked) return;

    setDeleteSaving(true);
    setDeleteError('');

    try {
      const adminDeleteInjuryCategory = httpsCallable(functions, 'adminDeleteInjuryCategory');
      await adminDeleteInjuryCategory({
        categoryId: injury.id,
        confirmation: deleteConfirmation,
      });

      setInjuries((prev) => prev.filter((item) => item.id !== injury.id));
      setSelectedInjuryId((prev) => (prev === injury.id ? null : prev));
      setDeleteSaving(false);
      closeDeleteDialog();
      setSuccessMsg('Injury category deleted successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to delete injury category:', err);
      setDeleteError(getCallableErrorMessage(err, 'Failed to delete injury category. Please try again.'));
    } finally {
      setDeleteSaving(false);
    }
  };

  const filtered = useMemo(() => {
    return injuries.filter((injury) => {
      const query = search.toLowerCase();
      return (
        !query ||
        (injury.name || '').toLowerCase().includes(query) ||
        (injury.bodyPart || '').toLowerCase().includes(query)
      );
    });
  }, [injuries, search]);

  const injuriesPagination = useClientPagination(filtered, {
    resetKey: search,
  });

  const selectedInjury = injuries.find((injury) => injury.id === selectedInjuryId) || null;
  const deleteInjury = injuries.find((injury) => injury.id === deleteState.injuryId) || null;

  const columns = [
    {
      key: 'injury',
      header: 'Injury',
      render: (injury) => <div className="wwin-name">{injury.name || '—'}</div>,
    },
    {
      key: 'bodyPart',
      header: 'Body Part',
      render: (injury) => <span className="wwin-body-part">{injury.bodyPart || '—'}</span>,
    },
    {
      key: 'description',
      header: 'Description',
      render: (injury) => <span className="wwin-description">{injury.description || '—'}</span>,
    },
  ];

  const openAddForm = () => {
    setSelectedInjuryId(null);
    setOpenInEdit(false);
    setShowAddForm(true);
    setAddError('');
    setAddForm(emptyForm);
  };

  return (
    <div className="wwin-page">
      <AdminStyles />
      <InjuriesStyles />

      <PageHeader
        title="Injuries"
        description="Manage injury categories used for exercise safety and filtering"
        count={loading ? undefined : `${injuries.length} injury categories`}
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
                Add Injury
              </button>
            </>
          ) : null
        }
      />

      {loading ? (
        <LoadingState rows={6} />
      ) : loadError ? (
        <ErrorState title="Failed to load injuries" message={loadError} onRetry={fetchData} />
      ) : (
        <>
          {showAddForm ? (
            <div className="wwa-panel wwin-form">
              <div>
                <div className="wwa-panel-title">Injury Details</div>
                <div className="wwa-panel-subtitle">Add a new injury category used across exercise safety workflows.</div>
              </div>

              {addError ? <div className="wwa-alert-error">{addError}</div> : null}

              <FormSection columns={2}>
                <FormField label="Name" labelFor="injury-name" required>
                  <input
                    id="injury-name"
                    className="wwa-input"
                    value={addForm.name}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, name: event.target.value }))}
                    placeholder="e.g. Lower Back"
                  />
                </FormField>

                <FormField label="Body Part" labelFor="injury-body-part" required>
                  <input
                    id="injury-body-part"
                    className="wwa-input"
                    value={addForm.bodyPart}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, bodyPart: event.target.value }))}
                    placeholder="e.g. Lower Back"
                  />
                </FormField>

                <FormField label="Description" labelFor="injury-description" required fullWidth>
                  <input
                    id="injury-description"
                    className="wwa-input"
                    value={addForm.description}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, description: event.target.value }))}
                    placeholder="e.g. Pain or discomfort in the lower back region"
                  />
                </FormField>
              </FormSection>

              <div className="wwin-form-actions">
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
                <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleAddInjury} disabled={addSaving}>
                  {addSaving ? 'Saving...' : 'Save Injury'}
                </button>
              </div>
            </div>
          ) : null}

          <div className={`wwin-layout ${selectedInjury ? 'has-detail' : ''}`}>
            <div>
              <FilterBar
                search={
                  <SearchInput
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    onClear={() => setSearch('')}
                    placeholder="Search by name or body part…"
                    label="Search injuries"
                  />
                }
                count={`${filtered.length} of ${injuries.length} injury categories`}
              />

              <DataTable
                className="wwin-table"
                columns={columns}
                rows={injuriesPagination.paginatedItems}
                getRowKey={(injury) => injury.id}
                selectedRowKey={selectedInjuryId}
                onRowClick={(injury) => openView(injury)}
                minWidth={760}
                pagination={{
                  currentPage: injuriesPagination.currentPage,
                  pageSize: injuriesPagination.pageSize,
                  totalItems: injuriesPagination.totalItems,
                  totalPages: injuriesPagination.totalPages,
                  pageSizeOptions: injuriesPagination.pageSizeOptions,
                  onPageChange: injuriesPagination.setCurrentPage,
                  onPageSizeChange: injuriesPagination.setPageSize,
                }}
                emptyIcon={null}
                emptyTitle="No injury categories found"
                emptyMessage={search ? 'Try a different search term.' : 'No injury categories added yet.'}
                renderRowActions={(injury) => (
                  <div className="wwin-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                      onClick={() => openView(injury)}
                      aria-label={`View ${injury.name || 'injury'}`}
                    >
                      <Eye aria-hidden="true" size={14} strokeWidth={2} />
                      View
                    </button>
                    <TableActions
                      label={`Actions for ${injury.name || 'injury'}`}
                      items={[
                        {
                          key: 'edit',
                          label: 'Edit',
                          icon: <Pencil aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openEdit(injury),
                        },
                        { type: 'divider' },
                        {
                          key: 'delete',
                          label: 'Delete',
                          tone: 'danger',
                          icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openDeleteDialog(injury),
                        },
                      ]}
                    />
                  </div>
                )}
              />
            </div>

            {selectedInjury ? (
              <InjuryDetailPanel
                injury={selectedInjury}
                startInEdit={openInEdit}
                onClose={() => setSelectedInjuryId(null)}
                onSave={handleSaveInjury}
                onEdit={openEdit}
                onDelete={openDeleteDialog}
              />
            ) : null}
          </div>
        </>
      )}

      <ModalDialog
        open={deleteState.open}
        title={deleteState.blocked ? 'Cannot Delete Injury Category' : 'Delete Injury Category'}
        description={
          deleteState.blocked
            ? undefined
            : 'This permanently removes the category from the injury library. Historical user injury entries may remain.'
        }
        onClose={closeDeleteDialog}
        footer={
          deleteState.blocked ? (
            <button type="button" className="wwa-btn wwa-btn-primary" onClick={closeDeleteDialog}>
              Close
            </button>
          ) : (
            <>
              <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeDeleteDialog} disabled={deleteSaving}>
                Cancel
              </button>
              <button
                type="button"
                className="wwa-btn wwa-btn-danger"
                onClick={handleDeleteInjury}
                disabled={deleteSaving || deleteConfirmation !== DELETE_CONFIRMATION}
              >
                {deleteSaving ? 'Deleting...' : 'Delete Injury Category'}
              </button>
            </>
          )
        }
      >
        {deleteState.blocked ? (
          <div className="wwin-modal-copy">
            This category is currently referenced by <strong>{deleteState.usageCount}</strong> exercise{deleteState.usageCount === 1 ? '' : 's'}. Remove the injury-risk references from those exercises before deleting the category.
          </div>
        ) : (
          <>
            <div className="wwin-modal-copy">
              Delete <strong>"{deleteInjury?.name || 'this category'}"</strong>?
            </div>
            <FormSection columns={1}>
              <FormField label="Confirmation" labelFor="injury-delete-confirmation" required fullWidth>
                <input
                  id="injury-delete-confirmation"
                  type="text"
                  className="wwa-input"
                  value={deleteConfirmation}
                  onChange={(event) => setDeleteConfirmation(event.target.value)}
                  placeholder={DELETE_CONFIRMATION}
                />
              </FormField>
            </FormSection>
            {deleteError ? <div className="wwa-alert-error">{deleteError}</div> : null}
          </>
        )}
      </ModalDialog>
    </div>
  );
}

export default Injuries;
