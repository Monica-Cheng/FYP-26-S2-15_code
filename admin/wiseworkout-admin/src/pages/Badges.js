import React, { useEffect, useState } from 'react';
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
import {
  formatConditions,
  validateConditions,
  normalizeConditionsForSave,
  isValidImageUrl,
} from '../utils/badgeUtils';

const emptyForm = { name: '', description: '', imageUrl: '', conditions: [{ statType: '', value: '' }] };

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
        margin-top: 3px;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwba-description {
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwba-condition {
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwba-condition + .wwba-condition {
        margin-top: 4px;
      }
      .wwba-image {
        width: 48px;
        height: 48px;
        border-radius: 12px;
        border: 1px solid var(--ww-divider);
        background: var(--ww-card);
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
      }
      .wwba-image img {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
      }
      .wwba-image__fallback {
        width: 100%;
        height: 100%;
        background: var(--ww-elevated);
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
    `}</style>
  );
}

function BadgeImage({ url, alt }) {
  if (!isValidImageUrl(url)) {
    return (
      <div className="wwba-image" aria-hidden="true">
        <div className="wwba-image__fallback" />
      </div>
    );
  }

  return (
    <div className="wwba-image">
      <img src={url} alt={alt} />
    </div>
  );
}

function Badges() {
  const [badges, setBadges] = useState([]);
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

  const fetchBadges = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminListBadgesDashboard = httpsCallable(functions, 'adminListBadgesDashboard');
      const result = await adminListBadgesDashboard();
      const data = result.data || {};
      setBadges(Array.isArray(data.badges) ? data.badges : []);
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
    if (!addForm.name.trim()) {
      setAddError('Badge Name is required.');
      return;
    }
    if (!addForm.description.trim()) {
      setAddError('Description is required.');
      return;
    }
    if (addForm.imageUrl.trim() && !isValidImageUrl(addForm.imageUrl)) {
      setAddError('Image URL must start with http:// or https://.');
      return;
    }

    const conditionsError = validateConditions(addForm.conditions);
    if (conditionsError) {
      setAddError(conditionsError);
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
      const detail = err?.code ? ` (${err.code})` : '';
      setAddError(`Failed to add badge. Please try again.${detail}`);
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

  const handleDeleteBadge = async (badgeId) => {
    const badge = badges.find((item) => item.id === badgeId);
    if (!badge) return;

    const confirmation = window.prompt(
      `Permanently delete "${badge.name || badgeId}"?\n\n` +
      'Deletion will be blocked if any user has already earned this badge.\n\n' +
      'Type DELETE BADGE exactly to continue:'
    );

    if (confirmation !== 'DELETE BADGE') return;

    try {
      const adminDeleteBadge = httpsCallable(functions, 'adminDeleteBadge');
      await adminDeleteBadge({
        badgeId,
        confirmation,
      });

      setBadges((prev) => prev.filter((item) => item.id !== badgeId));
      setSelectedBadgeId((prev) => (prev === badgeId ? null : prev));
      setSuccessMsg('Badge deleted successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to delete badge:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      window.alert(
        `Failed to delete badge.${detail}\n\n` +
        'The badge may already have been earned by a user.'
      );
    }
  };

  const filtered = badges.filter((badge) => {
    const query = search.toLowerCase();
    if (!query) return true;

    const matchesBasic =
      (badge.name || '').toLowerCase().includes(query) ||
      (badge.description || '').toLowerCase().includes(query);
    const matchesStat =
      Array.isArray(badge.conditions) &&
      badge.conditions.some((condition) => (condition?.statType || '').toLowerCase().includes(query));

    return matchesBasic || matchesStat;
  });

  const selectedBadge = badges.find((badge) => badge.id === selectedBadgeId) || null;

  const columns = [
    {
      key: 'badge',
      header: 'Badge',
      render: (badge) => (
        <div className="wwba-badge-cell">
          <div className="wwba-badge-cell__title">{badge.name || 'Unnamed badge'}</div>
          {badge.id ? <div className="wwba-badge-cell__meta">{badge.id}</div> : null}
        </div>
      ),
    },
    {
      key: 'description',
      header: 'Description',
      render: (badge) => <span className="wwba-description">{badge.description || '—'}</span>,
    },
    {
      key: 'condition',
      header: 'Condition',
      render: (badge) => {
        const conditionTexts = formatConditions(badge.conditions);
        if (conditionTexts === '—') return '—';

        return (
          <div>
            {conditionTexts.map((text, index) => (
              <div key={`${badge.id}-condition-${index}`} className="wwba-condition">
                {text}
              </div>
            ))}
          </div>
        );
      },
    },
    {
      key: 'image',
      header: 'Image',
      render: (badge) => <BadgeImage url={badge.imageUrl} alt={badge.name || 'Badge'} />,
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
                  />
                </FormField>
              </FormSection>

              <FormSection title="Earning Conditions" columns={1}>
                <ConditionsEditor
                  conditions={addForm.conditions}
                  onChange={(next) => setAddForm((prev) => ({ ...prev, conditions: next }))}
                  disabled={addSaving}
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
                rows={filtered}
                getRowKey={(badge) => badge.id}
                selectedRowKey={selectedBadgeId}
                minWidth={980}
                emptyIcon={null}
                emptyTitle="No badges found"
                emptyMessage={search ? 'Try a different search term.' : 'No badges added yet.'}
                renderRowActions={(badge) => (
                  <div className="wwba-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                      onClick={() => {
                        setShowAddForm(false);
                        setAddError('');
                        setSelectedBadgeId(badge.id);
                        setOpenInEdit(false);
                      }}
                      aria-label={`View ${badge.name || 'badge'}`}
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
                        setSelectedBadgeId(badge.id);
                        setOpenInEdit(true);
                      }}
                      aria-label={`Edit ${badge.name || 'badge'}`}
                    >
                      <Pencil aria-hidden="true" size={14} strokeWidth={2} />
                      Edit
                    </button>
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-danger"
                      onClick={() => handleDeleteBadge(badge.id)}
                      aria-label={`Delete ${badge.name || 'badge'}`}
                    >
                      <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                      Delete
                    </button>
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
              />
            ) : null}
          </div>
        </>
      )}
    </div>
  );
}

export default Badges;
