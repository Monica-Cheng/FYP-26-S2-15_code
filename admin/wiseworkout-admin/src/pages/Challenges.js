import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Eye, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import ChallengeCategoryDetailPanel from '../components/ChallengeCategoryDetailPanel';
import ChallengeDetailPanel from '../components/ChallengeDetailPanel';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import SelectField from '../components/ui/SelectField';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import DataTable from '../components/ui/DataTable';
import TableActions from '../components/ui/TableActions';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import ModalDialog from '../components/ui/ModalDialog';
import { getCallableErrorMessage } from '../utils/planUtils';
import {
  METRIC_TYPES,
  validateCategoryForm,
  resolveCategoryDisplay,
  formatGoal,
  computeChallengeStatus,
} from '../utils/challengeUtils';
import { formatDate } from '../utils/dateUtils';

const emptyCategoryForm = {
  name: '',
  unit: '',
  metricType: METRIC_TYPES[0],
  minGoal: '',
  maxGoal: '',
};

const emptyChallengeForm = {
  name: '',
  categoryId: '',
  goalValue: '',
  startDate: '',
  endDate: '',
};

const DELETE_CONFIRMATION = 'DELETE';

const statusTone = (status) =>
  status === 'Active' ? 'success' : status === 'Upcoming' ? 'brand' : 'neutral';

const sourceTone = (isGlobal) => (isGlobal ? 'brand' : 'neutral');

function ChallengesStyles() {
  return (
    <style>{`
      .wwch-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwch-section {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-4);
      }
      .wwch-panel {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-4);
      }
      .wwch-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwch-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
      }
      .wwch-panel-header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 16px;
        flex-wrap: wrap;
      }
      .wwch-panel-header__title {
        margin: 0;
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-primary-dark);
      }
      .wwch-panel-header__subtitle {
        margin: 6px 0 0;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-secondary-size);
      }
      .wwch-inline-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        flex-wrap: nowrap;
        white-space: nowrap;
      }
      .wwch-name-cell,
      .wwch-source-cell,
      .wwch-category-cell,
      .wwch-schedule-cell {
        min-width: 0;
      }
      .wwch-cell-title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwch-cell-meta {
        margin-top: 3px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
      }
      .wwch-badge-row {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }
      .wwch-add-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwch-form-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwch-alert-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwch-success {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 10px 14px;
        border-radius: 999px;
        background: rgba(79, 70, 229, 0.08);
        color: var(--ww-primary-dark);
        font-size: var(--ww-type-secondary-size);
        font-weight: 600;
      }
      .wwch-success::before {
        content: '';
        width: 8px;
        height: 8px;
        border-radius: 999px;
        background: var(--ww-primary);
      }
      .wwch-modal-copy {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwch-modal-note {
        margin-top: 10px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwch-grid-two {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 16px;
      }
      .wwch-grid-two .wwa-form-field-full {
        grid-column: 1 / -1;
      }
      .wwch-range-note {
        margin-top: 6px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
      }
      .wwch-empty-inline {
        padding: 4px 0;
      }
      @media (max-width: 720px) {
        .wwch-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
        }
        .wwch-grid-two {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

function normalizeText(value) {
  return (value || '').toString().trim().toLowerCase();
}

function getParticipantCount(challenge) {
  return Array.isArray(challenge?.participantUids) ? challenge.participantUids.length : 0;
}

function isChallengeDeletable(challenge) {
  return challenge?.isGlobal === true && getParticipantCount(challenge) === 0;
}

function getUserDisplay(user) {
  if (!user) return null;

  const fullName = [user.firstName, user.lastName].filter(Boolean).join(' ').trim();
  const name =
    user.displayName ||
    user.name ||
    fullName ||
    user.username ||
    user.email ||
    null;

  const email = typeof user.email === 'string' ? user.email.trim() : '';

  return {
    name: name || 'Unknown user',
    email,
  };
}

function resolveChallengeSource(challenge, usersById) {
  const creator = usersById.get(challenge?.createdBy);
  const creatorDisplay = getUserDisplay(creator);

  if (challenge?.isGlobal === true) {
    return {
      sourceLabel: 'Global',
      creatorName: 'Admin',
      creatorEmail: creatorDisplay?.email || '',
      technicalId: challenge?.createdBy || '',
      sourceDescription: 'Created by Admin',
    };
  }

  return {
    sourceLabel: 'User-created',
    creatorName: creatorDisplay?.name || 'Unknown user',
    creatorEmail: creatorDisplay?.email || '',
    technicalId: challenge?.createdBy || '',
    sourceDescription: `Created by ${creatorDisplay?.name || 'Unknown user'}`,
  };
}

function formatSchedule(challenge) {
  const start = formatDate(challenge?.startDate);
  const end = formatDate(challenge?.endDate);
  return {
    primary: start,
    secondary: end === '—' ? 'Ends —' : `Ends ${end}`,
  };
}

function Challenges() {
  const [challenges, setChallenges] = useState([]);
  const [categories, setCategories] = useState([]);
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState('');

  const [search, setSearch] = useState('');
  const [sourceFilter, setSourceFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [categoryFilter, setCategoryFilter] = useState('all');

  const [selectedChallengeId, setSelectedChallengeId] = useState(null);
  const [selectedCategoryId, setSelectedCategoryId] = useState(null);
  const [openCategoryInEdit, setOpenCategoryInEdit] = useState(false);

  const [showAddCategoryForm, setShowAddCategoryForm] = useState(false);
  const [addCategoryForm, setAddCategoryForm] = useState(emptyCategoryForm);
  const [addCategorySaving, setAddCategorySaving] = useState(false);
  const [addCategoryError, setAddCategoryError] = useState('');
  const [categorySuccessMsg, setCategorySuccessMsg] = useState('');

  const [showAddChallengeForm, setShowAddChallengeForm] = useState(false);
  const [addChallengeForm, setAddChallengeForm] = useState(emptyChallengeForm);
  const [addChallengeSaving, setAddChallengeSaving] = useState(false);
  const [addChallengeError, setAddChallengeError] = useState('');
  const [challengeSuccessMsg, setChallengeSuccessMsg] = useState('');

  const [deleteChallengeTarget, setDeleteChallengeTarget] = useState(null);
  const [deleteCategoryTarget, setDeleteCategoryTarget] = useState(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [deleteError, setDeleteError] = useState('');
  const [deleting, setDeleting] = useState(false);

  const usersById = useMemo(() => new Map(users.map((user) => [user.id, user])), [users]);

  const selectedCategory = useMemo(
    () => categories.find((category) => category.id === selectedCategoryId) || null,
    [categories, selectedCategoryId]
  );

  const selectedChallenge = useMemo(
    () => challenges.find((challenge) => challenge.id === selectedChallengeId) || null,
    [challenges, selectedChallengeId]
  );

  const selectedChallengeCategory = useMemo(
    () => categories.find((category) => category.id === addChallengeForm.categoryId) || null,
    [categories, addChallengeForm.categoryId]
  );

  const openChallengeView = useCallback((challenge) => {
    setSelectedCategoryId(null);
    setOpenCategoryInEdit(false);
    setSelectedChallengeId(challenge?.id || null);
  }, []);

  const openCategoryView = useCallback((category, { startInEdit = false } = {}) => {
    setSelectedChallengeId(null);
    setSelectedCategoryId(category?.id || null);
    setOpenCategoryInEdit(startInEdit);
  }, []);

  const categoryOptions = useMemo(
    () => [{ value: 'all', label: 'All' }, ...categories.map((category) => ({ value: category.id, label: category.name || category.id }))],
    [categories]
  );

  const fetchDashboard = useCallback(async ({ initial = false } = {}) => {
    if (initial) {
      setLoading(true);
    } else {
      setRefreshing(true);
    }
    setLoadError('');

    try {
      const adminListChallengeDashboard = httpsCallable(functions, 'adminListChallengeDashboard');
      const result = await adminListChallengeDashboard();
      const data = result.data || {};

      setChallenges(Array.isArray(data.challenges) ? data.challenges : []);
      setCategories(Array.isArray(data.categories) ? data.categories : []);
      setUsers(Array.isArray(data.users) ? data.users : []);
    } catch (error) {
      setLoadError(getCallableErrorMessage(error, 'Failed to load challenge dashboard.'));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    fetchDashboard({ initial: true });
  }, [fetchDashboard]);

  const countChallengesUsingCategory = useCallback(
    (categoryId) => challenges.filter((challenge) => challenge.categoryId === categoryId).length,
    [challenges]
  );

  const filteredChallenges = useMemo(() => {
    const query = normalizeText(search);

    return challenges.filter((challenge) => {
      const categoryDisplay = resolveCategoryDisplay(challenge.categoryId, categories);
      const creator = resolveChallengeSource(challenge, usersById);
      const status = computeChallengeStatus(challenge.startDate, challenge.endDate);
      const source = challenge.isGlobal === true ? 'global' : 'user';

      if (sourceFilter !== 'all' && source !== sourceFilter) {
        return false;
      }

      if (statusFilter !== 'all' && status !== statusFilter) {
        return false;
      }

      if (categoryFilter !== 'all' && challenge.categoryId !== categoryFilter) {
        return false;
      }

      if (!query) {
        return true;
      }

      return [
        challenge.name,
        challenge.title,
        categoryDisplay.text,
        creator.creatorName,
        creator.creatorEmail,
      ]
        .map(normalizeText)
        .some((value) => value.includes(query));
    });
  }, [categories, categoryFilter, challenges, search, sourceFilter, statusFilter, usersById]);

  const resetFilters = () => {
    setSearch('');
    setSourceFilter('all');
    setStatusFilter('all');
    setCategoryFilter('all');
  };

  const closeDeleteModal = () => {
    setDeleteChallengeTarget(null);
    setDeleteCategoryTarget(null);
    setDeleteConfirmation('');
    setDeleteError('');
    setDeleting(false);
  };

  const handleAddCategory = async () => {
    const validationError = validateCategoryForm(addCategoryForm);
    if (validationError) {
      setAddCategoryError(validationError);
      return;
    }

    setAddCategorySaving(true);
    setAddCategoryError('');

    try {
      const payload = {
        name: addCategoryForm.name.trim(),
        unit: addCategoryForm.unit.trim(),
        metricType: addCategoryForm.metricType,
        minGoal: Number(addCategoryForm.minGoal),
        maxGoal: Number(addCategoryForm.maxGoal),
      };

      const adminCreateChallengeCategory = httpsCallable(functions, 'adminCreateChallengeCategory');
      const result = await adminCreateChallengeCategory({ category: payload });

      setCategories((prev) => [
        ...prev,
        {
          id: result.data.categoryId,
          ...(result.data.category || payload),
        },
      ]);

      setShowAddCategoryForm(false);
      setAddCategoryForm(emptyCategoryForm);
      setCategorySuccessMsg('Category added successfully.');
    } catch (error) {
      setAddCategoryError(getCallableErrorMessage(error, 'Failed to add category. Please try again.'));
    } finally {
      setAddCategorySaving(false);
    }
  };

  const handleSaveCategory = async (categoryId, changes) => {
    const adminUpdateChallengeCategory = httpsCallable(functions, 'adminUpdateChallengeCategory');
    const result = await adminUpdateChallengeCategory({ categoryId, changes });
    const savedCategory = result.data.category || changes;

    setCategories((prev) =>
      prev.map((category) => (category.id === categoryId ? { ...category, ...savedCategory } : category))
    );
    setCategorySuccessMsg('Category updated successfully.');
  };

  const openDeleteCategoryModal = (category) => {
    setDeleteChallengeTarget(null);
    setDeleteCategoryTarget(category);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const handleDeleteCategory = async () => {
    if (!deleteCategoryTarget) return;

    setDeleting(true);
    setDeleteError('');

    try {
      const adminDeleteChallengeCategory = httpsCallable(functions, 'adminDeleteChallengeCategory');
      await adminDeleteChallengeCategory({ categoryId: deleteCategoryTarget.id });

      setCategories((prev) => prev.filter((item) => item.id !== deleteCategoryTarget.id));
      setSelectedCategoryId((prev) => (prev === deleteCategoryTarget.id ? null : prev));
      setOpenCategoryInEdit(false);
      setCategorySuccessMsg('Category deleted successfully.');
      closeDeleteModal();
    } catch (error) {
      setDeleteError(getCallableErrorMessage(error, 'Failed to delete category. Please try again.'));
      setDeleting(false);
    }
  };

  const handleAddChallenge = async () => {
    if (!addChallengeForm.name.trim()) {
      setAddChallengeError('Challenge name is required.');
      return;
    }

    const category = categories.find((item) => item.id === addChallengeForm.categoryId);
    if (!category) {
      setAddChallengeError('Select a category.');
      return;
    }

    const goalValue = Number(addChallengeForm.goalValue);
    if (addChallengeForm.goalValue === '' || !Number.isFinite(goalValue)) {
      setAddChallengeError('Goal value must be a valid number.');
      return;
    }

    if (goalValue < category.minGoal || goalValue > category.maxGoal) {
      setAddChallengeError(`Goal value must be between ${category.minGoal} and ${category.maxGoal} ${category.unit}.`);
      return;
    }

    if (!addChallengeForm.startDate) {
      setAddChallengeError('Start date is required.');
      return;
    }

    if (!addChallengeForm.endDate) {
      setAddChallengeError('End date is required.');
      return;
    }

    const startDateObj = new Date(addChallengeForm.startDate);
    const endDateObj = new Date(addChallengeForm.endDate);

    if (Number.isNaN(startDateObj.getTime()) || Number.isNaN(endDateObj.getTime())) {
      setAddChallengeError('Start date and end date must be valid dates.');
      return;
    }

    if (endDateObj <= startDateObj) {
      setAddChallengeError('End date must be after start date.');
      return;
    }

    setAddChallengeSaving(true);
    setAddChallengeError('');

    try {
      const adminCreateGlobalChallenge = httpsCallable(functions, 'adminCreateGlobalChallenge');
      const result = await adminCreateGlobalChallenge({
        challenge: {
          name: addChallengeForm.name.trim(),
          categoryId: category.id,
          metricType: category.metricType,
          unit: category.unit,
          goalValue,
          startDate: startDateObj.toISOString(),
          endDate: endDateObj.toISOString(),
        },
      });

      const savedChallenge = result.data.challenge || {};

      setChallenges((prev) => [
        ...prev,
        {
          id: result.data.challengeId,
          ...savedChallenge,
        },
      ]);

      setShowAddChallengeForm(false);
      setAddChallengeForm(emptyChallengeForm);
      setChallengeSuccessMsg('Global challenge created successfully.');
    } catch (error) {
      setAddChallengeError(getCallableErrorMessage(error, 'Failed to create challenge. Please try again.'));
    } finally {
      setAddChallengeSaving(false);
    }
  };

  const openDeleteChallengeModal = (challenge) => {
    if (!isChallengeDeletable(challenge)) return;
    setDeleteCategoryTarget(null);
    setDeleteChallengeTarget(challenge);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const handleDeleteChallenge = async () => {
    if (!deleteChallengeTarget) return;

    setDeleting(true);
    setDeleteError('');

    try {
      const adminDeleteChallenge = httpsCallable(functions, 'adminDeleteChallenge');
      await adminDeleteChallenge({ challengeId: deleteChallengeTarget.id });

      setChallenges((prev) => prev.filter((item) => item.id !== deleteChallengeTarget.id));
      setSelectedChallengeId((prev) => (prev === deleteChallengeTarget.id ? null : prev));
      setChallengeSuccessMsg('Global challenge deleted successfully.');
      closeDeleteModal();
    } catch (error) {
      setDeleteError(getCallableErrorMessage(error, 'Failed to delete challenge. Please try again.'));
      setDeleting(false);
    }
  };

  const challengeColumns = [
    {
      key: 'name',
      header: 'Challenge',
      render: (challenge) => {
        const creator = resolveChallengeSource(challenge, usersById);
        return (
          <div className="wwch-name-cell">
            <div className="wwch-cell-title">{challenge.name || challenge.title || '—'}</div>
            <div className="wwch-cell-meta">{creator.sourceDescription}</div>
          </div>
        );
      },
    },
    {
      key: 'category',
      header: 'Category',
      render: (challenge) => {
        const categoryDisplay = resolveCategoryDisplay(challenge.categoryId, categories);
        return (
          <div className="wwch-category-cell">
            <div className="wwch-cell-title">{categoryDisplay.text}</div>
            {categoryDisplay.missing ? <div className="wwch-cell-meta">Category not found</div> : null}
          </div>
        );
      },
    },
    {
      key: 'goal',
      header: 'Goal',
      render: (challenge) => <span>{formatGoal(challenge, categories)}</span>,
    },
    {
      key: 'schedule',
      header: 'Schedule',
      render: (challenge) => {
        const schedule = formatSchedule(challenge);
        return (
          <div className="wwch-schedule-cell">
            <div className="wwch-cell-title">{schedule.primary}</div>
            <div className="wwch-cell-meta">{schedule.secondary}</div>
          </div>
        );
      },
    },
    {
      key: 'source',
      header: 'Source',
      render: (challenge) => {
        const creator = resolveChallengeSource(challenge, usersById);
        return (
          <div className="wwch-source-cell">
            <div className="wwch-badge-row">
              <Badge tone={sourceTone(challenge.isGlobal === true)}>{creator.sourceLabel}</Badge>
            </div>
            <div className="wwch-cell-meta">{creator.creatorName}</div>
          </div>
        );
      },
    },
    {
      key: 'participants',
      header: 'Participants',
      numeric: true,
      render: (challenge) => getParticipantCount(challenge),
    },
    {
      key: 'status',
      header: 'Status',
      render: (challenge) => {
        const status = computeChallengeStatus(challenge.startDate, challenge.endDate);
        return <Badge tone={statusTone(status)}>{status}</Badge>;
      },
    },
  ];

  const categoryColumns = [
    {
      key: 'name',
      header: 'Category',
      render: (category) => (
        <div>
          <div className="wwch-cell-title">{category.name || '—'}</div>
          <div className="wwch-cell-meta">{category.unit || '—'}</div>
        </div>
      ),
    },
    {
      key: 'metricType',
      header: 'Metric',
      render: (category) => <Badge tone="neutral">{category.metricType || '—'}</Badge>,
    },
    {
      key: 'goalRange',
      header: 'Goal Range',
      render: (category) => `${category.minGoal ?? '—'}–${category.maxGoal ?? '—'} ${category.unit || ''}`.trim(),
    },
    {
      key: 'usage',
      header: 'Used By',
      numeric: true,
      render: (category) => countChallengesUsingCategory(category.id),
    },
  ];

  return (
    <div className="wwch-page">
      <AdminStyles />
      <ChallengesStyles />

      <PageHeader
        title="Challenges"
        subtitle="Manage global challenges and challenge categories."
        count={`${challenges.length} total challenges`}
        actions={(
          <>
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-secondary"
              onClick={() => fetchDashboard()}
              disabled={loading || refreshing}
            >
              <RefreshCw size={16} strokeWidth={2} />
              {refreshing ? 'Refreshing...' : 'Refresh'}
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-primary"
              onClick={() => {
                setShowAddChallengeForm((value) => !value);
                setAddChallengeError('');
                if (showAddChallengeForm) {
                  setAddChallengeForm(emptyChallengeForm);
                }
              }}
              disabled={categories.length === 0}
              title={categories.length === 0 ? 'Add a challenge category first.' : undefined}
            >
              <Plus size={16} strokeWidth={2} />
              Add Global Challenge
            </button>
          </>
        )}
      />

      {loading ? <LoadingState rows={10} /> : null}

      {!loading && loadError ? (
        <ErrorState
          title="Could not load challenges"
          message={loadError}
          onRetry={() => fetchDashboard()}
        />
      ) : null}

      {!loading && !loadError ? (
        <>
          {challengeSuccessMsg ? <div className="wwch-success">{challengeSuccessMsg}</div> : null}
          {categorySuccessMsg ? <div className="wwch-success">{categorySuccessMsg}</div> : null}

          {showAddChallengeForm ? (
            <div className="wwa-panel wwch-panel">
              <div className="wwch-panel-header">
                <div>
                  <h2 className="wwch-panel-header__title">New Global Challenge</h2>
                  <p className="wwch-panel-header__subtitle">
                    Global challenges inherit metric and unit rules from the selected category.
                  </p>
                </div>
              </div>

              {addChallengeError ? <div className="wwa-alert-error">{addChallengeError}</div> : null}

              <div className="wwch-add-form">
                <FormSection title="Challenge Details" columns={2}>
                  <FormField label="Challenge Name" required>
                    <input
                      className="wwa-input"
                      value={addChallengeForm.name}
                      onChange={(event) => setAddChallengeForm((prev) => ({ ...prev, name: event.target.value }))}
                      placeholder="e.g. April Distance Challenge"
                    />
                  </FormField>

                  <SelectField
                    label="Category"
                    required
                    value={addChallengeForm.categoryId}
                    onChange={(event) => setAddChallengeForm((prev) => ({ ...prev, categoryId: event.target.value }))}
                    options={categories.map((category) => ({
                      value: category.id,
                      label: `${category.name || category.id} (${category.metricType})`,
                    }))}
                    placeholder="Select a category"
                  />

                  <FormField
                    label="Goal Value"
                    required
                    helpText={
                      selectedChallengeCategory
                        ? `Allowed range: ${selectedChallengeCategory.minGoal}–${selectedChallengeCategory.maxGoal} ${selectedChallengeCategory.unit}`
                        : undefined
                    }
                  >
                    <input
                      type="number"
                      className="wwa-input"
                      value={addChallengeForm.goalValue}
                      onChange={(event) => setAddChallengeForm((prev) => ({ ...prev, goalValue: event.target.value }))}
                      placeholder={
                        selectedChallengeCategory
                          ? `${selectedChallengeCategory.minGoal}–${selectedChallengeCategory.maxGoal}`
                          : 'e.g. 50'
                      }
                    />
                  </FormField>

                  <FormField label="Metric" helpText="Derived from the selected category." optional>
                    <input className="wwa-input" value={selectedChallengeCategory?.metricType || 'Select a category'} readOnly />
                  </FormField>

                  <FormField label="Unit" helpText="Derived from the selected category." optional>
                    <input className="wwa-input" value={selectedChallengeCategory?.unit || 'Select a category'} readOnly />
                  </FormField>

                  <FormField label="Start Date" required>
                    <input
                      type="datetime-local"
                      className="wwa-input"
                      value={addChallengeForm.startDate}
                      onChange={(event) => setAddChallengeForm((prev) => ({ ...prev, startDate: event.target.value }))}
                    />
                  </FormField>

                  <FormField label="End Date" required>
                    <input
                      type="datetime-local"
                      className="wwa-input"
                      value={addChallengeForm.endDate}
                      onChange={(event) => setAddChallengeForm((prev) => ({ ...prev, endDate: event.target.value }))}
                    />
                  </FormField>
                </FormSection>

                <div className="wwch-form-actions">
                  <button type="button" className="wwa-btn wwa-btn-secondary" onClick={() => setShowAddChallengeForm(false)} disabled={addChallengeSaving}>
                    Cancel
                  </button>
                  <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleAddChallenge} disabled={addChallengeSaving}>
                    {addChallengeSaving ? 'Saving...' : 'Save Challenge'}
                  </button>
                </div>
              </div>
            </div>
          ) : null}

          <div className={`wwch-layout ${selectedChallenge || selectedCategory ? 'has-detail' : ''}`.trim()}>
            <div className="wwch-layout__main" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--ww-space-5)' }}>
              <div className="wwa-panel wwch-panel">
                <div className="wwch-panel-header">
                  <div>
                    <h2 className="wwch-panel-header__title">Challenges</h2>
                    <p className="wwch-panel-header__subtitle">
                      View global and user-created challenges without mutating membership data.
                    </p>
                  </div>
                </div>

                <FilterBar
                  search={(
                    <SearchInput
                      value={search}
                      onChange={(event) => setSearch(event.target.value)}
                      onClear={() => setSearch('')}
                      placeholder="Search challenges..."
                      label="Search challenges"
                    />
                  )}
                  filters={(
                    <>
                      <SelectField
                        label="Source"
                        value={sourceFilter}
                        onChange={(event) => setSourceFilter(event.target.value)}
                        options={[
                          { value: 'all', label: 'All' },
                          { value: 'global', label: 'Global' },
                          { value: 'user', label: 'User-created' },
                        ]}
                      />
                      <SelectField
                        label="Status"
                        value={statusFilter}
                        onChange={(event) => setStatusFilter(event.target.value)}
                        options={[
                          { value: 'all', label: 'All' },
                          { value: 'Upcoming', label: 'Upcoming' },
                          { value: 'Active', label: 'Active' },
                          { value: 'Ended', label: 'Ended' },
                        ]}
                      />
                      <SelectField
                        label="Category"
                        value={categoryFilter}
                        onChange={(event) => setCategoryFilter(event.target.value)}
                        options={categoryOptions}
                      />
                    </>
                  )}
                  onReset={resetFilters}
                  resetDisabled={search === '' && sourceFilter === 'all' && statusFilter === 'all' && categoryFilter === 'all'}
                  count={`${filteredChallenges.length} of ${challenges.length} challenges`}
                />

                <DataTable
                  className="wwch-table"
                  dense
                  columns={challengeColumns}
                  rows={filteredChallenges}
                  getRowKey={(challenge) => challenge.id}
                  selectedRowKey={selectedChallengeId}
                  onRowClick={(challenge) => openChallengeView(challenge)}
                  renderRowActions={(challenge) => {
                    const deletable = isChallengeDeletable(challenge);

                    return (
                      <div className="wwch-inline-actions">
                        <button
                          type="button"
                          className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                          onClick={(event) => {
                            event.stopPropagation();
                            openChallengeView(challenge);
                          }}
                        >
                          <Eye size={16} strokeWidth={2} />
                          View
                        </button>
                        {deletable ? (
                          <TableActions
                            label={`Actions for ${challenge.name || challenge.id}`}
                            items={[
                              {
                                key: 'delete',
                                label: 'Delete',
                                tone: 'danger',
                                icon: <Trash2 size={15} strokeWidth={2} />,
                                onSelect: () => openDeleteChallengeModal(challenge),
                              },
                            ]}
                          />
                        ) : null}
                      </div>
                    );
                  }}
                  emptyTitle="No challenges found"
                  emptyMessage="Try adjusting the filters or refresh the dashboard."
                />
              </div>

              <div className="wwa-panel wwch-panel">
                <div className="wwch-panel-header">
                  <div>
                    <h2 className="wwch-panel-header__title">Challenge Categories</h2>
                    <p className="wwch-panel-header__subtitle">Metric categories used when creating global challenges.</p>
                  </div>
                  <button
                    type="button"
                    className="wwa-btn wwa-btn-sm wwa-btn-primary"
                    onClick={() => {
                      setShowAddCategoryForm((value) => !value);
                      setAddCategoryError('');
                      if (showAddCategoryForm) {
                        setAddCategoryForm(emptyCategoryForm);
                      }
                    }}
                  >
                    <Plus size={16} strokeWidth={2} />
                    Add Category
                  </button>
                </div>

                {addCategoryError ? <div className="wwa-alert-error">{addCategoryError}</div> : null}

                {showAddCategoryForm ? (
                  <div className="wwch-add-form">
                    <FormSection title="New Category" columns={2}>
                      <FormField label="Category Name" required>
                        <input
                          className="wwa-input"
                          value={addCategoryForm.name}
                          onChange={(event) => setAddCategoryForm((prev) => ({ ...prev, name: event.target.value }))}
                          placeholder="e.g. Distance"
                        />
                      </FormField>

                      <FormField label="Unit" required>
                        <input
                          className="wwa-input"
                          value={addCategoryForm.unit}
                          onChange={(event) => setAddCategoryForm((prev) => ({ ...prev, unit: event.target.value }))}
                          placeholder="e.g. km"
                        />
                      </FormField>

                      <SelectField
                        label="Metric Type"
                        required
                        value={addCategoryForm.metricType}
                        onChange={(event) => setAddCategoryForm((prev) => ({ ...prev, metricType: event.target.value }))}
                        options={METRIC_TYPES}
                      />

                      <FormField label="Minimum Goal" required>
                        <input
                          type="number"
                          min="0"
                          className="wwa-input"
                          value={addCategoryForm.minGoal}
                          onChange={(event) => setAddCategoryForm((prev) => ({ ...prev, minGoal: event.target.value }))}
                        />
                      </FormField>

                      <FormField label="Maximum Goal" required>
                        <input
                          type="number"
                          min="0"
                          className="wwa-input"
                          value={addCategoryForm.maxGoal}
                          onChange={(event) => setAddCategoryForm((prev) => ({ ...prev, maxGoal: event.target.value }))}
                        />
                      </FormField>
                    </FormSection>

                    <div className="wwch-form-actions">
                      <button type="button" className="wwa-btn wwa-btn-secondary" onClick={() => setShowAddCategoryForm(false)} disabled={addCategorySaving}>
                        Cancel
                      </button>
                      <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleAddCategory} disabled={addCategorySaving}>
                        {addCategorySaving ? 'Saving...' : 'Save Category'}
                      </button>
                    </div>
                  </div>
                ) : null}

                <DataTable
                  className="wwch-table"
                  dense
                  columns={categoryColumns}
                  rows={categories}
                  getRowKey={(category) => category.id}
                  selectedRowKey={selectedCategoryId}
                  onRowClick={(category) => openCategoryView(category)}
                  renderRowActions={(category) => (
                    <div className="wwch-inline-actions">
                      <button
                        type="button"
                        className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                        onClick={(event) => {
                          event.stopPropagation();
                          openCategoryView(category);
                        }}
                      >
                        <Eye size={16} strokeWidth={2} />
                        View
                      </button>
                      <TableActions
                        label={`Actions for ${category.name || category.id}`}
                        items={[
                          {
                            key: 'edit',
                            label: 'Edit',
                            onSelect: () => openCategoryView(category, { startInEdit: true }),
                          },
                          {
                            key: 'delete',
                            label: 'Delete',
                            tone: 'danger',
                            icon: <Trash2 size={15} strokeWidth={2} />,
                            onSelect: () => openDeleteCategoryModal(category),
                          },
                        ]}
                      />
                    </div>
                  )}
                  emptyTitle="No categories yet"
                  emptyMessage="Add a category before creating a global challenge."
                />
              </div>
            </div>

            {selectedChallenge ? (
              <ChallengeDetailPanel
                challenge={selectedChallenge}
                categories={categories}
                usersById={usersById}
                onClose={() => setSelectedChallengeId(null)}
                onDelete={openDeleteChallengeModal}
              />
            ) : null}

            {!selectedChallenge && selectedCategory ? (
              <ChallengeCategoryDetailPanel
                category={selectedCategory}
                startInEdit={openCategoryInEdit}
                usageCount={selectedCategory ? countChallengesUsingCategory(selectedCategory.id) : 0}
                onClose={() => {
                  setSelectedCategoryId(null);
                  setOpenCategoryInEdit(false);
                }}
                onSave={handleSaveCategory}
                onDelete={openDeleteCategoryModal}
              />
            ) : null}
          </div>
        </>
      ) : null}

      <ModalDialog
        open={Boolean(deleteChallengeTarget)}
        title="Delete Challenge"
        description="This permanently removes the global challenge. A global challenge can only be deleted when it has no participants."
        onClose={closeDeleteModal}
        footer={(
          <>
            <button type="button" className="wwa-btn wwa-btn-secondary" onClick={closeDeleteModal} disabled={deleting}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={handleDeleteChallenge}
              disabled={deleteConfirmation !== DELETE_CONFIRMATION || deleting}
            >
              {deleting ? 'Deleting...' : 'Delete Challenge'}
            </button>
          </>
        )}
      >
        {deleteError ? <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{deleteError}</div> : null}
        <div className="wwch-modal-copy">
          Delete "{deleteChallengeTarget?.name || deleteChallengeTarget?.title || deleteChallengeTarget?.id}"?
        </div>
        <div className="wwch-modal-note">Confirmation</div>
        <input
          className="wwa-input"
          value={deleteConfirmation}
          onChange={(event) => setDeleteConfirmation(event.target.value)}
          placeholder={DELETE_CONFIRMATION}
          autoFocus
        />
      </ModalDialog>

      <ModalDialog
        open={Boolean(deleteCategoryTarget)}
        title="Delete Category"
        description="This permanently removes the challenge category. The backend will reject deletion while challenges still reference it."
        onClose={closeDeleteModal}
        footer={(
          <>
            <button type="button" className="wwa-btn wwa-btn-secondary" onClick={closeDeleteModal} disabled={deleting}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={handleDeleteCategory}
              disabled={deleteConfirmation !== DELETE_CONFIRMATION || deleting}
            >
              {deleting ? 'Deleting...' : 'Delete Category'}
            </button>
          </>
        )}
      >
        {deleteError ? <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{deleteError}</div> : null}
        <div className="wwch-modal-copy">
          Delete "{deleteCategoryTarget?.name || deleteCategoryTarget?.id}"?
        </div>
        <div className="wwch-modal-note">
          {deleteCategoryTarget
            ? `${countChallengesUsingCategory(deleteCategoryTarget.id)} challenge${countChallengesUsingCategory(deleteCategoryTarget.id) === 1 ? '' : 's'} currently reference this category.`
            : 'Confirmation'}
        </div>
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

export default Challenges;
