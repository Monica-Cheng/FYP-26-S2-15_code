import React, { useEffect, useMemo, useRef, useState } from 'react';
import { collection, getDocs } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import { Download, Eye, Pencil, Plus, Trash2 } from 'lucide-react';
import { db, functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import PlanDetailPanel from '../components/PlanDetailPanel';
import PlanSessionsEditor, {
  buildDefaultSessions,
  buildAndValidateSessions,
  resizeOfficialSessions,
  officialSessionsNeedTruncationConfirm,
} from '../components/PlanSessionsEditor';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import SelectField from '../components/ui/SelectField';
import DataTable from '../components/ui/DataTable';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import TableActions from '../components/ui/TableActions';
import ModalDialog from '../components/ui/ModalDialog';
import {
  parseCommaList,
  buildDesignedBy,
  CANONICAL_PLAN_TYPES,
  deriveOfficialMatchSport,
  getCallableErrorMessage,
} from '../utils/planUtils';

const CANONICAL_LEVELS = ['Beginner', 'Intermediate', 'Advanced'];
const CANONICAL_TYPES = CANONICAL_PLAN_TYPES;
const DELETE_CONFIRMATION = 'DELETE';

const getPlanSource = (plan) => {
  if (plan.isCoachPlan === true) return 'coach';
  if (plan.isCustom === true) return 'custom';
  return 'official';
};

const emptyAddForm = {
  name: '',
  level: 'Beginner',
  type: 'Gym',
  durationWeeks: '',
  daysPerWeek: '',
  equipment: '',
  description: '',
  goals: '',
  matchGoals: '',
  matchLevel: 'Beginner',
  isActive: true,
  featured: false,
  imageUrl: '',
  designedByName: '',
  designedByTitle: '',
  designedByCredential: '',
  designedByQuote: '',
};

const buildOfficialDurationReductionWarning = (oldWeeks, newWeeks) =>
  `Reducing duration from ${oldWeeks} week${oldWeeks === 1 ? '' : 's'} to ${newWeeks} week${newWeeks === 1 ? '' : 's'} will remove day entries from the end of the plan. Continue?`;

function PlansStyles() {
  return (
    <style>{`
      .wwpl-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwpl-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwpl-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) minmax(400px, var(--ww-drawer-width-wide));
        align-items: start;
      }
      .wwpl-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwpl-form-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwpl-table .wwa-table th:last-child,
      .wwpl-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwpl-plan-cell,
      .wwpl-creator-cell,
      .wwpl-schedule-cell {
        min-width: 0;
      }
      .wwpl-plan-cell__title,
      .wwpl-creator-cell__title,
      .wwpl-schedule-cell__title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
        line-height: 1.35;
      }
      .wwpl-plan-cell__meta,
      .wwpl-creator-cell__meta,
      .wwpl-schedule-cell__meta {
        margin-top: 3px;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwpl-plan-cell__meta {
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .wwpl-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        white-space: nowrap;
      }
      .wwpl-status-badge {
        white-space: nowrap;
      }
      .wwpl-modal-copy {
        color: var(--ww-text-sec);
        line-height: 1.5;
      }
      .wwpl-catalog-state {
        display: flex;
        flex-direction: column;
        gap: 12px;
        padding: 16px;
        border: 1px dashed var(--ww-divider);
        border-radius: 14px;
        background: color-mix(in srgb, var(--ww-elevated) 60%, white);
      }
      .wwpl-catalog-state__title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwpl-catalog-state__meta {
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.5;
      }
      .wwpl-catalog-state__actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
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
        .wwpl-layout.has-detail {
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

function Plans() {
  const [plans, setPlans] = useState([]);
  const [usersById, setUsersById] = useState({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [search, setSearch] = useState('');
  const [levelFilter, setLevelFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all');
  const [sourceFilter, setSourceFilter] = useState('all');
  const [daysFilter, setDaysFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedPlanId, setSelectedPlanId] = useState(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [addForm, setAddForm] = useState(emptyAddForm);
  const [addSessions, setAddSessions] = useState(() => buildDefaultSessions(emptyAddForm.daysPerWeek, emptyAddForm.durationWeeks, emptyAddForm.type));
  const [addSaving, setAddSaving] = useState(false);
  const [addError, setAddError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [exerciseCatalog, setExerciseCatalog] = useState([]);
  const [exerciseCatalogLoading, setExerciseCatalogLoading] = useState(false);
  const [exerciseCatalogLoaded, setExerciseCatalogLoaded] = useState(false);
  const [exerciseCatalogError, setExerciseCatalogError] = useState('');
  const [openInEdit, setOpenInEdit] = useState(false);
  const [deletePlan, setDeletePlan] = useState(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [deleteSaving, setDeleteSaving] = useState(false);
  const [deleteError, setDeleteError] = useState('');
  const [pendingAddDurationReduction, setPendingAddDurationReduction] = useState(null);
  const exerciseCatalogRequestRef = useRef(null);

  const fetchData = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminListPlansDashboard = httpsCallable(functions, 'adminListPlansDashboard');
      const result = await adminListPlansDashboard();
      const data = result.data || {};

      const loadedPlans = Array.isArray(data.plans) ? data.plans : [];
      setPlans(loadedPlans);

      const byId = {};
      const loadedUsers = Array.isArray(data.users) ? data.users : [];
      loadedUsers.forEach((user) => {
        byId[user.id] = user;
      });
      setUsersById(byId);
    } catch (err) {
      console.error('Failed to load plans dashboard:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setLoadError(`Failed to load plans dashboard.${detail}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const ensureExerciseCatalogLoaded = async () => {
    if (exerciseCatalogLoaded) {
      return exerciseCatalog;
    }

    if (exerciseCatalogRequestRef.current) {
      return exerciseCatalogRequestRef.current;
    }

    setExerciseCatalogLoading(true);
    setExerciseCatalogError('');

    const request = getDocs(collection(db, 'exercises'))
      .then((snapshot) => {
        const catalog = snapshot.docs
          .map((doc) => ({ id: doc.id, ...doc.data() }))
          .filter((exercise) => exercise.name)
          .map((exercise) => ({
            name: exercise.name,
            muscle: typeof exercise.muscle === 'string' ? exercise.muscle.trim() : '',
            muscleGroup: typeof exercise.muscleGroup === 'string' ? exercise.muscleGroup.trim() : '',
          }));

        setExerciseCatalog(catalog);
        setExerciseCatalogLoaded(true);
        setExerciseCatalogError('');
        return catalog;
      })
      .catch((err) => {
        console.error('Failed to load exercise catalog:', err);
        const detail = err?.code ? ` (${err.code})` : '';
        const message = `Failed to load exercise catalog.${detail}`;
        setExerciseCatalogError(message);
        throw err;
      })
      .finally(() => {
        setExerciseCatalogLoading(false);
        exerciseCatalogRequestRef.current = null;
      });

    exerciseCatalogRequestRef.current = request;
    return request;
  };

  const getCreatorLabel = (plan) => {
    if (!plan.isCustom) return (plan.designedBy && plan.designedBy.name) || 'WiseWorkout';
    const uid = plan.createdBy;
    if (!uid) return '—';
    const user = usersById[uid];
    return (user && (user.displayName || user.email)) || uid;
  };

  const levels = useMemo(
    () => Array.from(new Set(plans.map((plan) => plan.level).filter(Boolean))).sort(),
    [plans]
  );
  const types = useMemo(
    () => Array.from(new Set(plans.map((plan) => plan.type).filter(Boolean))).sort(),
    [plans]
  );
  const daysOptions = useMemo(
    () =>
      Array.from(
        new Set(plans.map((plan) => plan.daysPerWeek).filter((days) => days !== undefined && days !== null))
      ).sort((a, b) => a - b),
    [plans]
  );

  const levelOptions = useMemo(
    () => Array.from(new Set([...CANONICAL_LEVELS, ...levels])).filter((level) => level.toLowerCase() !== 'custom'),
    [levels]
  );
  const officialTypeOptions = CANONICAL_TYPES;

  const handleAddPlan = async () => {
    if (!exerciseCatalogReady) {
      setAddError(exerciseCatalogLoading ? 'Exercise catalog is still loading. Please wait before saving.' : exerciseCatalogError || 'Exercise catalog is unavailable. Retry loading it before saving.');
      return;
    }

    if (!addForm.name.trim()) {
      setAddError('Plan Name is required.');
      return;
    }
    if (!addForm.level) {
      setAddError('Level is required.');
      return;
    }
    if (!addForm.type) {
      setAddError('Type is required.');
      return;
    }

    const days = Number(addForm.daysPerWeek);
    if (!Number.isInteger(days) || days <= 0) {
      setAddError('Days per Week must be a valid positive integer.');
      return;
    }

    const durationWeeks = Number(addForm.durationWeeks);
    if (!Number.isInteger(durationWeeks) || durationWeeks <= 0) {
      setAddError('Duration (weeks) must be a valid positive integer.');
      return;
    }

    const { sessions, error: sessionsError } = buildAndValidateSessions(
      addSessions,
      days,
      addForm.type,
      exerciseCatalog,
      durationWeeks
    );
    if (sessionsError) {
      setAddError(sessionsError);
      return;
    }

    const equipmentList = parseCommaList(addForm.equipment);
    const goalsList = parseCommaList(addForm.goals);
    const matchGoalsList = parseCommaList(addForm.matchGoals);
    const designedBy = buildDesignedBy({
      name: addForm.designedByName,
      title: addForm.designedByTitle,
      credential: addForm.designedByCredential,
      quote: addForm.designedByQuote,
    });

    setAddSaving(true);
    setAddError('');

    try {
      const payload = {
        name: addForm.name.trim(),
        level: addForm.level,
        type: addForm.type,
        daysPerWeek: days,
        durationWeeks,
        description: addForm.description.trim(),
        equipment: equipmentList,
        goals: goalsList,
        sessions,
        isActive: addForm.isActive,
        featured: addForm.featured === true,
        matchGoals: matchGoalsList,
        matchLevel: addForm.matchLevel || addForm.level,
        matchSport: deriveOfficialMatchSport(addForm.type),
        imageUrl: addForm.imageUrl.trim(),
      };
      if (designedBy) payload.designedBy = designedBy;

      const adminCreateOfficialPlan = httpsCallable(functions, 'adminCreateOfficialPlan');
      const result = await adminCreateOfficialPlan({
        plan: payload,
      });

      setPlans((prev) => [
        ...prev,
        {
          id: result.data.planId,
          ...(result.data.plan || payload),
        },
      ]);
      setShowAddForm(false);
      setAddForm(emptyAddForm);
      setAddSessions(buildDefaultSessions(emptyAddForm.daysPerWeek, emptyAddForm.durationWeeks, emptyAddForm.type));
      setSuccessMsg('Plan created successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setAddError(getCallableErrorMessage(err, 'Failed to create plan. Please try again.'));
    }

    setAddSaving(false);
  };

  const handleSavePlan = async (planId, changes) => {
    try {
      const adminUpdatePlan = httpsCallable(functions, 'adminUpdatePlan');
      const result = await adminUpdatePlan({
        planId,
        changes,
      });

      const savedPlan = result.data.plan || changes;

      setPlans((prev) =>
        prev.map((plan) =>
          plan.id === planId
            ? {
                ...plan,
                ...savedPlan,
                updatedAt: new Date().toISOString(),
              }
            : plan
        )
      );
    } catch (err) {
      console.error(err);
      throw new Error(getCallableErrorMessage(err, 'Failed to update plan. Please try again.'));
    }
  };

  const handleDeletePlan = async (plan) => {
    try {
      setDeleteSaving(true);
      setDeleteError('');
      const adminDeletePlan = httpsCallable(functions, 'adminDeletePlan');
      await adminDeletePlan({
        planId: plan.id,
      });
    } catch (err) {
      console.error(err);
      throw new Error(getCallableErrorMessage(err, 'Failed to delete plan. Please try again.'));
    } finally {
      setDeleteSaving(false);
    }

    setPlans((prev) => prev.filter((existing) => existing.id !== plan.id));
    setSelectedPlanId(null);
    setOpenInEdit(false);
    setDeletePlan(null);
    setDeleteConfirmation('');
    setDeleteError('');
    setSuccessMsg(`${sourceLabel(plan)} plan deleted successfully`);
    setTimeout(() => setSuccessMsg(''), 3000);
  };

  const hasActiveFilters = Boolean(
    search || levelFilter !== 'all' || typeFilter !== 'all' || sourceFilter !== 'all' || daysFilter !== 'all' || statusFilter !== 'all'
  );

  const resetFilters = () => {
    setSearch('');
    setLevelFilter('all');
    setTypeFilter('all');
    setSourceFilter('all');
    setDaysFilter('all');
    setStatusFilter('all');
  };

  const filtered = useMemo(() => {
    const query = search.toLowerCase();
    return plans.filter((plan) => {
      const matchesSearch =
        !query ||
        (plan.title || plan.name || '').toLowerCase().includes(query) ||
        (plan.level || '').toLowerCase().includes(query);
      const matchesLevel = levelFilter === 'all' || plan.level === levelFilter;
      const matchesType = typeFilter === 'all' || plan.type === typeFilter;
      const matchesSource = sourceFilter === 'all' || getPlanSource(plan) === sourceFilter;
      const matchesDays = daysFilter === 'all' || plan.daysPerWeek === Number(daysFilter);
      const matchesStatus =
        statusFilter === 'all' ||
        (statusFilter === 'active' ? plan.isActive !== false : plan.isActive === false);

      return matchesSearch && matchesLevel && matchesType && matchesSource && matchesDays && matchesStatus;
    });
  }, [plans, search, levelFilter, typeFilter, sourceFilter, daysFilter, statusFilter]);

  const selectedPlan = useMemo(
    () => plans.find((plan) => plan.id === selectedPlanId) || null,
    [plans, selectedPlanId]
  );

  const levelTone = (level) =>
    level === 'Advanced' ? 'danger' : level === 'Intermediate' ? 'warning' : 'success';

  const sourceTone = (plan) =>
    getPlanSource(plan) === 'coach' ? 'warning' : getPlanSource(plan) === 'custom' ? 'brand' : 'neutral';

  const sourceLabel = (plan) =>
    getPlanSource(plan) === 'coach' ? 'Coach' : getPlanSource(plan) === 'custom' ? 'Custom' : 'Official/System';

  const scheduleLabel = (plan) => {
    const parts = [];
    if (plan.daysPerWeek) parts.push(`${plan.daysPerWeek} days/week`);
    if (plan.durationWeeks) parts.push(`${plan.durationWeeks} weeks`);
    return parts.length > 0 ? parts.join(' · ') : '—';
  };

  const handleExport = () => {
    const rows = filtered.map((plan) => {
      const creator = getCreatorLabel(plan);
      return {
        'Plan Name': plan.title || plan.name || '-',
        Level: plan.level || '-',
        Duration: plan.durationWeeks ? `${plan.durationWeeks}w` : '-',
        'Days/Week': plan.daysPerWeek ? `${plan.daysPerWeek} days` : '-',
        Equipment: Array.isArray(plan.equipment)
          ? plan.equipment.length > 0
            ? plan.equipment.join(', ')
            : '-'
          : plan.equipment || '-',
        Type: plan.type || plan.category || '-',
        Source: sourceLabel(plan),
        Creator: creator === '—' ? '-' : creator,
      };
    });

    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 26 }, { wch: 12 }, { wch: 10 }, { wch: 12 }, { wch: 30 }, { wch: 10 }, { wch: 10 }, { wch: 22 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Plans');
    XLSX.writeFile(workbook, 'WiseWorkout_Plans.xlsx');
  };

  const columns = [
    {
      key: 'plan',
      header: 'Plan',
      render: (plan) => (
        <div className="wwpl-plan-cell">
          <div className="wwpl-plan-cell__title">{plan.title || plan.name || '—'}</div>
          {plan.description ? <div className="wwpl-plan-cell__meta">{plan.description}</div> : null}
        </div>
      ),
    },
    {
      key: 'level',
      header: 'Level',
      render: (plan) => <Badge tone={levelTone(plan.level)}>{plan.level || 'Beginner'}</Badge>,
    },
    {
      key: 'type',
      header: 'Type',
      render: (plan) => <Badge tone="brand">{plan.type || plan.category || 'General'}</Badge>,
    },
    {
      key: 'schedule',
      header: 'Schedule',
      render: (plan) => (
        <div className="wwpl-schedule-cell">
          <div className="wwpl-schedule-cell__title">{scheduleLabel(plan)}</div>
        </div>
      ),
    },
    {
      key: 'source',
      header: 'Source',
      render: (plan) => <Badge tone={sourceTone(plan)}>{sourceLabel(plan)}</Badge>,
    },
    {
      key: 'creator',
      header: 'Creator',
      render: (plan) => (
        <div className="wwpl-creator-cell">
          <div className="wwpl-creator-cell__title">{getCreatorLabel(plan)}</div>
        </div>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (plan) => (
        <Badge tone={plan.isActive !== false ? 'success' : 'danger'} className="wwpl-status-badge">
          {plan.isActive !== false ? 'Active' : 'Inactive'}
        </Badge>
      ),
    },
  ];

  const openAddForm = () => {
    setSelectedPlanId(null);
    setOpenInEdit(false);
    setShowAddForm(true);
    setAddError('');
    setPendingAddDurationReduction(null);
    setAddForm(emptyAddForm);
    setAddSessions(buildDefaultSessions(emptyAddForm.daysPerWeek, emptyAddForm.durationWeeks, emptyAddForm.type));
    void ensureExerciseCatalogLoaded();
  };

  const openPlanView = (plan) => {
    setShowAddForm(false);
    setAddError('');
    setPendingAddDurationReduction(null);
    setSelectedPlanId(plan.id);
    setOpenInEdit(false);
  };

  const openPlanEdit = (plan) => {
    setShowAddForm(false);
    setAddError('');
    setPendingAddDurationReduction(null);
    setSelectedPlanId(plan.id);
    setOpenInEdit(true);
    void ensureExerciseCatalogLoaded();
  };

  const exerciseCatalogReady = exerciseCatalogLoaded && !exerciseCatalogLoading;

  const renderExerciseCatalogState = (variant) => (
    <div className="wwpl-catalog-state">
      <div className="wwpl-catalog-state__title">
        {exerciseCatalogLoading ? 'Loading exercise catalog…' : 'Exercise catalog unavailable'}
      </div>
      <div className="wwpl-catalog-state__meta">
        {exerciseCatalogLoading
          ? `Loading exercises for ${variant === 'add' ? 'plan creation' : 'plan editing'}. The rest of the page remains available.`
          : exerciseCatalogError || 'The exercise catalog could not be loaded.'}
      </div>
      {!exerciseCatalogLoading ? (
        <div className="wwpl-catalog-state__actions">
          <button type="button" className="wwa-btn wwa-btn-secondary" onClick={() => void ensureExerciseCatalogLoaded()}>
            Retry
          </button>
        </div>
      ) : null}
    </div>
  );

  const openDeleteDialog = (plan) => {
    setDeletePlan(plan);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const closeDeleteDialog = () => {
    if (deleteSaving) return;
    setDeletePlan(null);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const handleDeleteConfirm = async () => {
    if (!deletePlan) return;
    try {
      await handleDeletePlan(deletePlan);
    } catch (err) {
      setDeleteError(err?.message || 'Failed to delete plan. Please try again.');
    }
  };

  const closeAddDurationReductionDialog = () => {
    setPendingAddDurationReduction(null);
  };

  const confirmAddDurationReduction = () => {
    if (!pendingAddDurationReduction) return;
    setAddSessions(pendingAddDurationReduction.sessions);
    setAddForm((prev) => ({ ...prev, durationWeeks: pendingAddDurationReduction.value }));
    setPendingAddDurationReduction(null);
  };

  const handleAddDurationWeeksChange = (value) => {
    const currentWeeks = Number(addForm.durationWeeks) || 1;
    const requestedWeeks = Number(value);

    if (!Number.isInteger(requestedWeeks) || requestedWeeks <= 0) {
      setAddForm((prev) => ({ ...prev, durationWeeks: value }));
      return;
    }

    const { sessions: resizedSessions, removedSessions } = resizeOfficialSessions(addSessions, requestedWeeks);
    if (
      requestedWeeks < currentWeeks &&
      officialSessionsNeedTruncationConfirm(removedSessions)
    ) {
      setPendingAddDurationReduction({
        value,
        sessions: resizedSessions,
        oldWeeks: currentWeeks,
        newWeeks: requestedWeeks,
      });
      return;
    }

    setAddSessions(resizedSessions);
    setAddForm((prev) => ({ ...prev, durationWeeks: value }));
  };

  return (
    <div className="wwpl-page">
      <AdminStyles />
      <PlansStyles />

      <PageHeader
        title="Plans"
        description="Manage official, coach, and custom plans"
        count={loading ? undefined : `${plans.length} plans in the library`}
        actions={
          !loading ? (
            <>
              {successMsg ? (
                <span className="wwa-status-pill">
                  <span className="wwa-status-dot" />
                  {successMsg}
                </span>
              ) : null}
              <button type="button" className="wwa-btn wwa-btn-secondary" onClick={handleExport} disabled={filtered.length === 0}>
                <Download aria-hidden="true" size={16} strokeWidth={2} />
                Export to Excel
              </button>
              <button type="button" className="wwa-btn wwa-btn-primary" onClick={openAddForm}>
                <Plus aria-hidden="true" size={16} strokeWidth={2} />
                Add Plan
              </button>
            </>
          ) : null
        }
      />

      {loading ? (
        <LoadingState rows={6} />
      ) : loadError ? (
        <ErrorState title="Failed to load plans" message={loadError} onRetry={fetchData} />
      ) : (
        <>
          {showAddForm ? (
            <div className="wwa-panel wwpl-form">
              <div>
                <div className="wwa-panel-title">New Official Plan</div>
                <div className="wwa-panel-subtitle">Creates a system plan and preserves the existing official plan schema.</div>
              </div>

              {addError ? <div className="wwa-alert-error">{addError}</div> : null}

              <FormSection title="Basic Information" columns={2}>
                <FormField label="Plan Name" labelFor="plan-name" required>
                  <input
                    id="plan-name"
                    className="wwa-input"
                    value={addForm.name}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, name: event.target.value }))}
                    placeholder="e.g. Fat Loss Circuit"
                  />
                </FormField>

                <SelectField
                  id="plan-level"
                  label="Level"
                  value={addForm.level}
                  onChange={(event) => setAddForm((prev) => ({ ...prev, level: event.target.value, matchLevel: event.target.value }))}
                  options={levelOptions}
                />

                <SelectField
                  id="plan-type"
                  label="Type"
                  value={addForm.type}
                  onChange={(event) => setAddForm((prev) => ({ ...prev, type: event.target.value }))}
                  options={officialTypeOptions}
                />

                <FormField label="Days per Week" labelFor="plan-days" required>
                  <input
                    id="plan-days"
                    type="number"
                    min="1"
                    className="wwa-input"
                    value={addForm.daysPerWeek}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, daysPerWeek: event.target.value }))}
                    placeholder="e.g. 3"
                  />
                </FormField>

                <FormField label="Duration (weeks)" labelFor="plan-duration" required>
                  <input
                    id="plan-duration"
                    type="number"
                    min="1"
                    className="wwa-input"
                    value={addForm.durationWeeks}
                    onChange={(event) => handleAddDurationWeeksChange(event.target.value)}
                    placeholder="e.g. 8"
                  />
                </FormField>

                <FormField label="Status" labelFor="plan-status" fullWidth>
                  <label id="plan-status" className="wwa-toggle-inline">
                    <input
                      type="checkbox"
                      checked={addForm.isActive}
                      onChange={(event) => setAddForm((prev) => ({ ...prev, isActive: event.target.checked }))}
                    />
                    <span>Active (visible to users)</span>
                  </label>
                </FormField>

                <FormField label="Featured Plan" labelFor="plan-featured" fullWidth>
                  <label id="plan-featured" className="wwa-toggle-inline">
                    <input
                      type="checkbox"
                      checked={addForm.featured}
                      onChange={(event) => setAddForm((prev) => ({ ...prev, featured: event.target.checked }))}
                    />
                    <span>Highlight this official plan in featured placements</span>
                  </label>
                </FormField>
              </FormSection>

              <FormSection title="Plan Matching" columns={2}>
                <FormField label="Match Sport" labelFor="plan-match-sport">
                  <input
                    id="plan-match-sport"
                    className="wwa-input"
                    value={deriveOfficialMatchSport(addForm.type)}
                    readOnly
                    disabled
                  />
                </FormField>

                <FormField label="Match Level" labelFor="plan-match-level">
                  <input
                    id="plan-match-level"
                    className="wwa-input"
                    value={addForm.matchLevel}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, matchLevel: event.target.value }))}
                  />
                </FormField>

                <FormField label="Goals" labelFor="plan-goals">
                  <input
                    id="plan-goals"
                    className="wwa-input"
                    value={addForm.goals}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, goals: event.target.value }))}
                    placeholder="Comma-separated, e.g. Build Muscle, Build Strength"
                  />
                </FormField>

                <FormField label="Equipment" labelFor="plan-equipment">
                  <input
                    id="plan-equipment"
                    className="wwa-input"
                    value={addForm.equipment}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, equipment: event.target.value }))}
                    placeholder="Comma-separated, e.g. Barbell, Dumbbells, Bench"
                  />
                </FormField>

                <FormField label="Match Goals" labelFor="plan-match-goals" fullWidth>
                  <input
                    id="plan-match-goals"
                    className="wwa-input"
                    value={addForm.matchGoals}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, matchGoals: event.target.value }))}
                    placeholder="Comma-separated — feeds the Plan Match algorithm"
                  />
                </FormField>
              </FormSection>

              <FormSection title="Presentation" columns={2}>
                <FormField label="Description" labelFor="plan-description" fullWidth>
                  <input
                    id="plan-description"
                    className="wwa-input"
                    value={addForm.description}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, description: event.target.value }))}
                    placeholder="Short description shown to users"
                  />
                </FormField>

                <FormField label="Image URL" labelFor="plan-image-url">
                  <input
                    id="plan-image-url"
                    className="wwa-input"
                    value={addForm.imageUrl}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, imageUrl: event.target.value }))}
                    placeholder="https://… (optional)"
                  />
                </FormField>
              </FormSection>

              <FormSection title="Designed By" description="Optional plan attribution shown to users." columns={2}>
                <FormField label="Name" labelFor="designer-name">
                  <input
                    id="designer-name"
                    className="wwa-input"
                    value={addForm.designedByName}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, designedByName: event.target.value }))}
                  />
                </FormField>

                <FormField label="Title" labelFor="designer-title">
                  <input
                    id="designer-title"
                    className="wwa-input"
                    value={addForm.designedByTitle}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, designedByTitle: event.target.value }))}
                  />
                </FormField>

                <FormField label="Credential" labelFor="designer-credential">
                  <input
                    id="designer-credential"
                    className="wwa-input"
                    value={addForm.designedByCredential}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, designedByCredential: event.target.value }))}
                  />
                </FormField>

                <FormField label="Quote" labelFor="designer-quote" fullWidth>
                  <input
                    id="designer-quote"
                    className="wwa-input"
                    value={addForm.designedByQuote}
                    onChange={(event) => setAddForm((prev) => ({ ...prev, designedByQuote: event.target.value }))}
                  />
                </FormField>
              </FormSection>

              <FormSection title="Training Schedule" description="Official plans use explicit day entries grouped by week across the full duration." columns={1}>
                {exerciseCatalogReady ? (
                  <PlanSessionsEditor
                    sessions={addSessions}
                    onChange={setAddSessions}
                    exerciseCatalog={exerciseCatalog}
                    mode="official"
                    planType={addForm.type}
                  />
                ) : (
                  renderExerciseCatalogState('add')
                )}
              </FormSection>

              <div className="wwpl-form-actions">
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
                <button
                  type="button"
                  className="wwa-btn wwa-btn-primary"
                  onClick={handleAddPlan}
                  disabled={addSaving || !exerciseCatalogReady}
                >
                  {addSaving ? 'Saving...' : 'Save Plan'}
                </button>
              </div>
            </div>
          ) : null}

          <div className={`wwpl-layout ${selectedPlan ? 'has-detail' : ''}`}>
            <div>
              <FilterBar
                search={
                  <SearchInput
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    onClear={() => setSearch('')}
                    placeholder="Search plans…"
                    label="Search plans"
                  />
                }
                filters={
                  <>
                    <SelectField
                      value={levelFilter}
                      onChange={(event) => setLevelFilter(event.target.value)}
                      options={[{ value: 'all', label: 'Level: All' }, ...levels.map((level) => ({ value: level, label: level }))]}
                      aria-label="Filter plans by level"
                    />
                    <SelectField
                      value={typeFilter}
                      onChange={(event) => setTypeFilter(event.target.value)}
                      options={[{ value: 'all', label: 'Type: All' }, ...types.map((type) => ({ value: type, label: type }))]}
                      aria-label="Filter plans by type"
                    />
                    <SelectField
                      value={sourceFilter}
                      onChange={(event) => setSourceFilter(event.target.value)}
                      options={[
                        { value: 'all', label: 'Source: All' },
                        { value: 'official', label: 'Source: Official/System' },
                        { value: 'coach', label: 'Source: Coach' },
                        { value: 'custom', label: 'Source: Custom' },
                      ]}
                      aria-label="Filter plans by source"
                    />
                    <SelectField
                      value={daysFilter}
                      onChange={(event) => setDaysFilter(event.target.value)}
                      options={[{ value: 'all', label: 'Days/Week: All' }, ...daysOptions.map((days) => ({ value: String(days), label: `${days} days/week` }))]}
                      aria-label="Filter plans by days per week"
                    />
                    <SelectField
                      value={statusFilter}
                      onChange={(event) => setStatusFilter(event.target.value)}
                      options={[
                        { value: 'all', label: 'Status: All' },
                        { value: 'active', label: 'Status: Active' },
                        { value: 'inactive', label: 'Status: Inactive' },
                      ]}
                      aria-label="Filter plans by status"
                    />
                  </>
                }
                onReset={resetFilters}
                resetLabel="Reset filters"
                resetVariant="secondary"
                resetDisabled={!hasActiveFilters}
                count={`${filtered.length} of ${plans.length} plans`}
              />

              <DataTable
                className="wwpl-table"
                columns={columns}
                rows={filtered}
                getRowKey={(plan) => plan.id}
                selectedRowKey={selectedPlanId}
                onRowClick={(plan) => openPlanView(plan)}
                minWidth={1080}
                emptyIcon={null}
                emptyTitle="No plans found"
                emptyMessage={hasActiveFilters ? 'Try adjusting your search or filters.' : 'No plans in the library yet.'}
                renderRowActions={(plan) => (
                  <div className="wwpl-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                      onClick={(event) => {
                        event.stopPropagation();
                        openPlanView(plan);
                      }}
                      aria-label={`View ${plan.title || plan.name || 'plan'}`}
                    >
                      <Eye aria-hidden="true" size={14} strokeWidth={2} />
                      View
                    </button>
                    <TableActions
                      label={`Actions for ${plan.title || plan.name || 'plan'}`}
                      items={[
                        {
                          key: 'edit',
                          label: 'Edit',
                          icon: <Pencil aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openPlanEdit(plan),
                        },
                        { type: 'divider' },
                        {
                          key: 'delete',
                          label: 'Delete',
                          tone: 'danger',
                          icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                          onSelect: () => openDeleteDialog(plan),
                        },
                      ]}
                    />
                  </div>
                )}
              />
            </div>

            {selectedPlan ? (
              <PlanDetailPanel
                plan={selectedPlan}
                creatorLabel={getCreatorLabel(selectedPlan)}
                levelOptions={levelOptions}
                typeOptions={officialTypeOptions}
                exerciseCatalog={exerciseCatalog}
                exerciseCatalogReady={exerciseCatalogReady}
                exerciseCatalogLoading={exerciseCatalogLoading}
                exerciseCatalogError={exerciseCatalogError}
                onRetryExerciseCatalog={ensureExerciseCatalogLoaded}
                startInEdit={openInEdit}
                onClose={() => {
                  setSelectedPlanId(null);
                  setOpenInEdit(false);
                }}
                onSave={handleSavePlan}
                onEdit={openPlanEdit}
                onDelete={openDeleteDialog}
              />
            ) : null}
          </div>
        </>
      )}

      <ModalDialog
        open={Boolean(pendingAddDurationReduction)}
        title="Reduce Plan Duration?"
        description="Reducing the duration removes sessions that fall outside the new plan length."
        onClose={closeAddDurationReductionDialog}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeAddDurationReductionDialog}>
              Cancel
            </button>
            <button type="button" className="wwa-btn wwa-btn-primary" onClick={confirmAddDurationReduction}>
              Continue
            </button>
          </>
        }
      >
        <div className="wwpl-modal-copy">
          {pendingAddDurationReduction
            ? buildOfficialDurationReductionWarning(
                pendingAddDurationReduction.oldWeeks,
                pendingAddDurationReduction.newWeeks
              )
            : ''}
          <br />
          <br />
          Populated day entries outside the new duration will be removed.
        </div>
      </ModalDialog>

      <ModalDialog
        open={Boolean(deletePlan)}
        title="Delete Plan"
        description="This permanently removes the selected plan. This action cannot be undone."
        onClose={closeDeleteDialog}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeDeleteDialog} disabled={deleteSaving}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={handleDeleteConfirm}
              disabled={deleteSaving || deleteConfirmation !== DELETE_CONFIRMATION}
            >
              {deleteSaving ? 'Deleting...' : 'Delete Plan'}
            </button>
          </>
        }
      >
        <div className="wwpl-modal-copy">
          Delete <strong>"{deletePlan?.title || deletePlan?.name || 'this plan'}"</strong>?
          {deletePlan ? (
            <>
              <br />
              <br />
              {deletePlan.isCustom
                ? 'This also removes the creator’s matching custom routine and plan progress.'
                : 'This removes the official plan from the shared plan library.'}
            </>
          ) : null}
        </div>
        <FormSection columns={1}>
          <FormField label="Confirmation" labelFor="plan-delete-confirmation" required fullWidth>
            <input
              id="plan-delete-confirmation"
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

export default Plans;
