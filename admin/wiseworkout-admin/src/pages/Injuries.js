import React, { useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Eye, Pencil, Plus, Trash2 } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import InjuryDetailPanel from '../components/InjuryDetailPanel';
import DataTable from '../components/ui/DataTable';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';

const emptyForm = { name: '', bodyPart: '', description: '' };

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
      @media (max-width: 1120px) {
        .wwin-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
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
      const detail = err?.code ? ` (${err.code})` : '';
      setLoadError(`Failed to load injuries dashboard.${detail}`);
      window.alert(`Failed to load injuries dashboard.${detail}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const countExercisesUsingInjury = (injuryName) => {
    const lower = (injuryName || '').toLowerCase();
    return exercises.filter((exercise) =>
      Array.isArray(exercise.injuryRisk) &&
      exercise.injuryRisk.some((risk) => (risk || '').toLowerCase() === lower)
    ).length;
  };

  const handleAddInjury = async () => {
    if (!addForm.name.trim()) {
      setAddError('Name is required.');
      return;
    }
    if (!addForm.bodyPart.trim()) {
      setAddError('Body Part is required.');
      return;
    }
    if (!addForm.description.trim()) {
      setAddError('Description is required.');
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
      const detail = err?.code ? ` (${err.code})` : '';
      setAddError(`Failed to add injury category. Please try again.${detail}`);
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

  const handleDeleteInjury = async (injuryId) => {
    const injury = injuries.find((item) => item.id === injuryId);
    if (!injury) return;

    const usageCount = countExercisesUsingInjury(injury.name);
    if (usageCount > 0) {
      window.alert(
        `"${injury.name}" is currently used by ` +
        `${usageCount} exercise${usageCount === 1 ? '' : 's'}. ` +
        'Remove this injury risk from those exercises before deleting the category.'
      );
      return;
    }

    const confirmation = window.prompt(
      `Permanently delete "${injury.name}"?\n\n` +
      'Type DELETE INJURY exactly to continue:'
    );

    if (confirmation !== 'DELETE INJURY') return;

    const adminDeleteInjuryCategory = httpsCallable(functions, 'adminDeleteInjuryCategory');
    await adminDeleteInjuryCategory({
      categoryId: injuryId,
      confirmation,
    });

    setInjuries((prev) => prev.filter((item) => item.id !== injuryId));
    setSelectedInjuryId((prev) => (prev === injuryId ? null : prev));
    setSuccessMsg('Injury category deleted successfully');
    setTimeout(() => setSuccessMsg(''), 3000);
  };

  const filtered = injuries.filter((injury) => {
    const query = search.toLowerCase();
    return (
      !query ||
      (injury.name || '').toLowerCase().includes(query) ||
      (injury.bodyPart || '').toLowerCase().includes(query)
    );
  });

  const selectedInjury = injuries.find((injury) => injury.id === selectedInjuryId) || null;

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
                rows={filtered}
                getRowKey={(injury) => injury.id}
                selectedRowKey={selectedInjuryId}
                minWidth={760}
                emptyIcon={null}
                emptyTitle="No injury categories found"
                emptyMessage={search ? 'Try a different search term.' : 'No injury categories added yet.'}
                renderRowActions={(injury) => (
                  <div className="wwin-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                      onClick={() => {
                        setShowAddForm(false);
                        setAddError('');
                        setSelectedInjuryId(injury.id);
                        setOpenInEdit(false);
                      }}
                      aria-label={`View ${injury.name || 'injury'}`}
                    >
                      <Eye aria-hidden="true" size={14} strokeWidth={2} />
                      View
                    </button>
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                      onClick={() => {
                        setShowAddForm(false);
                        setAddError('');
                        setSelectedInjuryId(injury.id);
                        setOpenInEdit(true);
                      }}
                      aria-label={`Edit ${injury.name || 'injury'}`}
                    >
                      <Pencil aria-hidden="true" size={14} strokeWidth={2} />
                      Edit
                    </button>
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-danger"
                      onClick={() => handleDeleteInjury(injury.id)}
                      aria-label={`Delete ${injury.name || 'injury'}`}
                    >
                      <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                      Delete
                    </button>
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
              />
            ) : null}
          </div>
        </>
      )}
    </div>
  );
}

export default Injuries;
