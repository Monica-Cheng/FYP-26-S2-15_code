import React, { useEffect, useState } from 'react';
import { CalendarDays, Clock3, Dumbbell, Pencil, Trash2 } from 'lucide-react';
import Badge from './ui/Badge';
import DetailDrawer from './ui/DetailDrawer';
import FormSection from './ui/FormSection';
import FormField from './ui/FormField';
import SelectField from './ui/SelectField';
import PlanSessionsEditor, {
  buildDefaultSessions,
  buildAndValidateSessions,
  sessionsFromPlan,
  buildDefaultCustomSessions,
  buildAndValidateCustomSessions,
  customSessionsFromPlan,
  resizeOfficialSessions,
  officialSessionsNeedTruncationConfirm,
} from './PlanSessionsEditor';
import { formatDate } from '../utils/dateUtils';
import { formatEquipment } from '../utils/formatUtils';
import {
  parseCommaList,
  formatCommaList,
  buildDesignedBy,
  deriveOfficialMatchSport,
  normalizeOfficialPlanType,
} from '../utils/planUtils';

const SET_TYPE_LABELS = { W: 'Warmup', N: 'Normal', D: 'Drop Set' };

const getPlanSource = (plan) => {
  if (plan.isCoachPlan === true) return 'coach';
  if (plan.isCustom === true) return 'custom';
  return 'official';
};

const sourceLabel = (plan) =>
  getPlanSource(plan) === 'coach' ? 'Coach' : getPlanSource(plan) === 'custom' ? 'Custom' : 'Official/System';

const sourceTone = (plan) =>
  getPlanSource(plan) === 'coach' ? 'warning' : getPlanSource(plan) === 'custom' ? 'brand' : 'neutral';

const levelTone = (level) =>
  level === 'Advanced' ? 'danger' : level === 'Intermediate' ? 'warning' : 'success';

const isValidImageUrl = (url) => /^https?:\/\//i.test((url || '').trim());
const buildOfficialDurationReductionWarning = (oldWeeks, newWeeks) =>
  `Reducing duration from ${oldWeeks} week${oldWeeks === 1 ? '' : 's'} to ${newWeeks} week${newWeeks === 1 ? '' : 's'} will remove day entries from the end of the plan. Continue?`;

function PlanDetailStyles() {
  return (
    <style>{`
      .wwpdn-summary {
        display: flex;
        gap: 16px;
        align-items: flex-start;
      }
      .wwpdn-summary__media {
        width: 96px;
        height: 96px;
        border-radius: 16px;
        border: 1px solid var(--ww-divider);
        background: var(--ww-card);
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .wwpdn-summary__media img {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
      }
      .wwpdn-summary__fallback {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--ww-elevated);
        color: var(--ww-text-sec);
        font-size: var(--ww-type-secondary-size);
      }
      .wwpdn-summary__content {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwpdn-summary__title {
        font-size: var(--ww-type-page-title-size);
        font-weight: var(--ww-type-page-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.15;
      }
      .wwpdn-summary__meta {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwpdn-message-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwpdn-message-stack .wwa-status-pill,
      .wwpdn-message-stack .wwa-alert-error {
        margin: 0;
      }
      .wwpdn-description {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
        white-space: pre-wrap;
      }
      .wwpdn-list {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwpdn-list-item {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
        padding: 6px 10px;
        border-radius: 999px;
        background: var(--ww-elevated);
        color: var(--ww-text);
        font-size: var(--ww-type-secondary-size);
        font-weight: 600;
      }
      .wwpdn-designer-quote {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text-sec);
        line-height: 1.6;
        font-style: italic;
      }
      .wwpdn-schedule {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwpdn-session {
        border: 1px solid var(--ww-divider);
        border-radius: 14px;
        background: var(--ww-card);
        overflow: hidden;
      }
      .wwpdn-session__header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 14px 16px;
        background: color-mix(in srgb, var(--ww-bg) 76%, white);
        border-bottom: 1px solid var(--ww-divider);
        flex-wrap: wrap;
      }
      .wwpdn-session__title-group {
        min-width: 0;
      }
      .wwpdn-session__eyebrow {
        font-size: var(--ww-type-caption-size);
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--ww-text-sec);
      }
      .wwpdn-session__title {
        margin-top: 4px;
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-primary-dark);
      }
      .wwpdn-session__meta {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwpdn-session__rest {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 16px;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-body-size);
      }
      .wwpdn-session__items {
        display: flex;
        flex-direction: column;
      }
      .wwpdn-item {
        padding: 14px 16px;
        border-top: 1px solid var(--ww-divider);
      }
      .wwpdn-item:first-child {
        border-top: 0;
      }
      .wwpdn-item__header {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }
      .wwpdn-item__title {
        font-size: var(--ww-type-body-size);
        font-weight: 700;
        color: var(--ww-text);
      }
      .wwpdn-item__meta {
        margin-top: 6px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwpdn-item__note {
        margin-top: 8px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text);
        line-height: 1.55;
      }
      .wwpdn-set-list {
        margin-top: 10px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .wwpdn-set-row {
        display: grid;
        grid-template-columns: minmax(0, 1.2fr) minmax(80px, auto) minmax(80px, auto);
        gap: 10px;
        align-items: center;
        padding: 10px 12px;
        border-radius: 10px;
        background: var(--ww-elevated);
        color: var(--ww-text);
        font-size: var(--ww-type-table-body-size);
      }
      .wwpdn-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwpdn-footer {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwpdn-footer__primary {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
        margin-left: auto;
      }
      .wwpdn-form-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 16px;
      }
      .wwpdn-meta-value {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
      }
      @media (max-width: 720px) {
        .wwpdn-summary {
          flex-direction: column;
        }
        .wwpdn-summary__media {
          width: 100%;
          max-width: 180px;
        }
        .wwpdn-set-row {
          grid-template-columns: minmax(0, 1fr);
        }
        .wwpdn-form-grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

function DetailRow({ label, value, multiline = false }) {
  if (value === undefined || value === null || value === '') return null;

  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      {multiline ? <div className="wwpdn-description">{value}</div> : <span className="wwa-detail-value">{value}</span>}
    </div>
  );
}

function ListRow({ label, values }) {
  if (!Array.isArray(values) || values.length === 0) return null;

  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <div className="wwpdn-list">
        {values.map((value, index) => (
          <span key={`${label}-${index}-${value}`} className="wwpdn-list-item">
            {value}
          </span>
        ))}
      </div>
    </div>
  );
}

function SetList({ sets }) {
  if (Array.isArray(sets)) {
    if (sets.length === 0) {
      return <div className="wwpdn-item__meta">No set data</div>;
    }

    return (
      <div className="wwpdn-set-list">
        {sets.map((setItem, index) => (
          <div key={`set-${index}`} className="wwpdn-set-row">
            <div>{SET_TYPE_LABELS[setItem?.type] || setItem?.type || 'Set'}</div>
            <div>{setItem?.kg === '' || setItem?.kg === undefined || setItem?.kg === null ? '—' : `${setItem.kg} kg`}</div>
            <div>{setItem?.reps === '' || setItem?.reps === undefined || setItem?.reps === null ? '—' : `${setItem.reps} reps`}</div>
          </div>
        ))}
      </div>
    );
  }

  if (typeof sets === 'number') {
    return <div className="wwpdn-item__meta">{sets} sets</div>;
  }

  return <div className="wwpdn-item__meta">No set data</div>;
}

function ExerciseRow({ exercise }) {
  if (exercise && exercise.isCardio === true) {
    return (
      <div className="wwpdn-item">
        <div className="wwpdn-item__header">
          <Clock3 aria-hidden="true" size={16} strokeWidth={2} />
          <div className="wwpdn-item__title">{exercise.name || 'Cardio block'}</div>
          <Badge tone="brand">Cardio</Badge>
          {exercise.tag ? <Badge tone={exercise.tag === 'Primary' ? 'brand' : 'neutral'}>{exercise.tag}</Badge> : null}
        </div>
        <div className="wwpdn-item__meta">
          {exercise.cardioActivity || '—'}
          {exercise.cardioMinutes !== undefined && exercise.cardioMinutes !== null ? ` · ${exercise.cardioMinutes} min` : ''}
        </div>
      </div>
    );
  }

  return (
    <div className="wwpdn-item">
      <div className="wwpdn-item__header">
        <Dumbbell aria-hidden="true" size={16} strokeWidth={2} />
        <div className="wwpdn-item__title">{exercise.name || 'Unnamed exercise'}</div>
        {exercise.tag ? <Badge tone={exercise.tag === 'Primary' ? 'brand' : 'neutral'}>{exercise.tag}</Badge> : null}
      </div>
      <div className="wwpdn-item__meta">
        {exercise.muscle || '—'}
        {exercise.restTime !== undefined && exercise.restTime !== null ? ` · Rest ${exercise.restTime}s` : ''}
      </div>
      {exercise.note ? <div className="wwpdn-item__note">{exercise.note}</div> : null}
      <SetList sets={exercise.sets} />
    </div>
  );
}

function SessionCard({ session, index }) {
  const dayNumber = session.dayNumber ?? (index + 1);
  const label = session.name || session.day || session.label || `Day ${dayNumber}`;
  const isRestDay = !!session.isRestDay;
  const exercises = Array.isArray(session.exercises) ? session.exercises : [];

  return (
    <div className="wwpdn-session">
      <div className="wwpdn-session__header">
        <div className="wwpdn-session__title-group">
          <div className="wwpdn-session__eyebrow">Day {dayNumber}</div>
          <div className="wwpdn-session__title">{label}</div>
        </div>
        <div className="wwpdn-session__meta">
          {session.type ? <Badge tone="neutral">{session.type}</Badge> : null}
          {session.estimatedMinutes ? <Badge tone="neutral">{session.estimatedMinutes} min</Badge> : null}
          {isRestDay ? <Badge tone="neutral">Rest Day</Badge> : <Badge tone="neutral">{exercises.length} item{exercises.length === 1 ? '' : 's'}</Badge>}
        </div>
      </div>

      {isRestDay ? (
        <div className="wwpdn-session__rest">
          <CalendarDays aria-hidden="true" size={16} strokeWidth={2} />
          <span>Rest day</span>
        </div>
      ) : (
        <div className="wwpdn-session__items">
          {exercises.length > 0 ? exercises.map((exercise, index) => <ExerciseRow key={index} exercise={exercise} />) : <div className="wwpdn-session__rest">No exercises recorded for this session.</div>}
        </div>
      )}
    </div>
  );
}

function PlanDetailPanel({ plan, creatorLabel, levelOptions, typeOptions, exerciseCatalog, onClose, onSave, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [customSessions, setCustomSessions] = useState([]);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const planId = plan ? plan.id : null;

  const [isEditingOfficial, setIsEditingOfficial] = useState(false);
  const [officialForm, setOfficialForm] = useState(null);
  const [officialSessions, setOfficialSessions] = useState([]);
  const [officialSaving, setOfficialSaving] = useState(false);

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setCustomSessions([]);
    setError('');
    setSuccessMsg('');
    setDeleting(false);
    setIsEditingOfficial(false);
    setOfficialForm(null);
    setOfficialSessions([]);
  }, [planId]);

  if (!plan) return null;

  const sessions = Array.isArray(plan.sessions) ? plan.sessions : [];
  const isCustom = !!plan.isCustom;
  const isActive = plan.isActive !== false;
  const isFeatured = plan.featured === true;
  const designedBy = plan.designedBy && typeof plan.designedBy === 'object' ? plan.designedBy : null;
  const isEditMode = isEditing || isEditingOfficial;
  const canEdit = typeof onSave === 'function';
  const canDelete = typeof onDelete === 'function';

  const startEdit = () => {
    setForm({
      name: plan.name || '',
      description: plan.description || '',
      daysPerWeek: plan.daysPerWeek ?? '',
    });
    setCustomSessions(sessions.length > 0 ? customSessionsFromPlan(sessions) : buildDefaultCustomSessions(plan.daysPerWeek));
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  };

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    if (!form.name.trim()) {
      setError('Plan Name cannot be empty.');
      return;
    }
    const days = Number(form.daysPerWeek);
    if (!Number.isInteger(days) || days <= 0) {
      setError('Days per Week must be a valid positive integer.');
      return;
    }

    const { sessions: builtSessions, error: sessionsError } = buildAndValidateCustomSessions(
      customSessions,
      plan.type,
      exerciseCatalog || []
    );
    if (sessionsError) {
      setError(sessionsError);
      return;
    }

    const changes = {};
    if (form.name.trim() !== (plan.name || '')) changes.name = form.name.trim();
    if (form.description.trim() !== (plan.description || '')) changes.description = form.description.trim();
    if (days !== plan.daysPerWeek) changes.daysPerWeek = days;
    if (JSON.stringify(builtSessions) !== JSON.stringify(sessions)) changes.sessions = builtSessions;

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');
    try {
      await onSave(plan.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('Plan updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setError('Failed to update plan. Please try again.');
    }
    setSaving(false);
  };

  const startEditOfficial = () => {
    setOfficialForm({
      name: plan.name || '',
      description: plan.description || '',
      level: plan.level || (levelOptions && levelOptions[0]) || 'Beginner',
      type: normalizeOfficialPlanType(plan.type),
      daysPerWeek: plan.daysPerWeek ?? '',
      durationWeeks: plan.durationWeeks ?? '',
      equipment: formatCommaList(plan.equipment),
      goals: formatCommaList(plan.goals),
      matchGoals: formatCommaList(plan.matchGoals),
      matchLevel: plan.matchLevel || plan.level || '',
      isActive: plan.isActive !== false,
      featured: plan.featured === true,
      imageUrl: plan.imageUrl || '',
      designedByName: designedBy?.name || '',
      designedByTitle: designedBy?.title || '',
      designedByCredential: designedBy?.credential || '',
      designedByQuote: designedBy?.quote || '',
    });
    setOfficialSessions(
      sessions.length > 0 ? sessionsFromPlan(sessions) : buildDefaultSessions(plan.daysPerWeek, plan.durationWeeks, plan.type)
    );
    setError('');
    setSuccessMsg('');
    setIsEditingOfficial(true);
  };

  const cancelEditOfficial = () => {
    setIsEditingOfficial(false);
    setOfficialForm(null);
    setError('');
  };

  const handleSaveOfficial = async () => {
    if (!officialForm.name.trim()) {
      setError('Plan Name cannot be empty.');
      return;
    }
    if (!officialForm.level) {
      setError('Level is required.');
      return;
    }
    if (!officialForm.type) {
      setError('Type is required.');
      return;
    }
    const days = Number(officialForm.daysPerWeek);
    if (!Number.isInteger(days) || days <= 0) {
      setError('Days per Week must be a valid positive integer.');
      return;
    }
    const durationWeeks = Number(officialForm.durationWeeks);
    if (!Number.isInteger(durationWeeks) || durationWeeks <= 0) {
      setError('Duration (weeks) must be a valid positive integer.');
      return;
    }

    const { sessions: builtSessions, error: sessionsError } = buildAndValidateSessions(
      officialSessions,
      days,
      officialForm.type,
      exerciseCatalog || [],
      durationWeeks
    );
    if (sessionsError) {
      setError(sessionsError);
      return;
    }

    const equipmentList = parseCommaList(officialForm.equipment);
    const goalsList = parseCommaList(officialForm.goals);
    const matchGoalsList = parseCommaList(officialForm.matchGoals);
    const newDesignedBy = buildDesignedBy({
      name: officialForm.designedByName,
      title: officialForm.designedByTitle,
      credential: officialForm.designedByCredential,
      quote: officialForm.designedByQuote,
    });

    const changes = {};
    const derivedMatchSport = deriveOfficialMatchSport(officialForm.type);
    if (officialForm.name.trim() !== (plan.name || '')) changes.name = officialForm.name.trim();
    if (officialForm.description.trim() !== (plan.description || '')) changes.description = officialForm.description.trim();
    if (officialForm.level !== plan.level) changes.level = officialForm.level;
    if (officialForm.type !== plan.type) changes.type = officialForm.type;
    if (days !== plan.daysPerWeek) changes.daysPerWeek = days;
    if (durationWeeks !== plan.durationWeeks) changes.durationWeeks = durationWeeks;
    const existingEquipment = Array.isArray(plan.equipment) ? plan.equipment : [];
    if (JSON.stringify(equipmentList) !== JSON.stringify(existingEquipment)) changes.equipment = equipmentList;
    const existingGoals = Array.isArray(plan.goals) ? plan.goals : [];
    if (JSON.stringify(goalsList) !== JSON.stringify(existingGoals)) changes.goals = goalsList;
    const existingMatchGoals = Array.isArray(plan.matchGoals) ? plan.matchGoals : [];
    if (JSON.stringify(matchGoalsList) !== JSON.stringify(existingMatchGoals)) changes.matchGoals = matchGoalsList;
    if (derivedMatchSport !== (plan.matchSport || '')) changes.matchSport = derivedMatchSport;
    if (officialForm.matchLevel !== (plan.matchLevel || '')) changes.matchLevel = officialForm.matchLevel;
    if (officialForm.isActive !== isActive) changes.isActive = officialForm.isActive;
    if (officialForm.featured !== isFeatured) changes.featured = officialForm.featured;
    if (officialForm.imageUrl.trim() !== (plan.imageUrl || '')) changes.imageUrl = officialForm.imageUrl.trim();
    if (newDesignedBy && JSON.stringify(newDesignedBy) !== JSON.stringify(designedBy || undefined)) {
      changes.designedBy = newDesignedBy;
    } else if (!newDesignedBy && designedBy) {
      changes.designedBy = null;
    }
    if (JSON.stringify(builtSessions) !== JSON.stringify(sessions)) changes.sessions = builtSessions;

    if (Object.keys(changes).length === 0) {
      setIsEditingOfficial(false);
      setOfficialForm(null);
      return;
    }

    setOfficialSaving(true);
    setError('');
    try {
      await onSave(plan.id, changes);
      setIsEditingOfficial(false);
      setOfficialForm(null);
      setSuccessMsg('Plan updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setError(err?.message || 'Failed to update plan. Please try again.');
    }
    setOfficialSaving(false);
  };

  const handleDeleteClick = async () => {
    const confirmMsg = isCustom
      ? 'Are you sure you want to permanently delete this custom plan? This action cannot be undone.'
      : 'Are you sure you want to permanently delete this official plan? This action cannot be undone.';
    if (!window.confirm(confirmMsg)) {
      return;
    }
    setDeleting(true);
    setError('');
    try {
      await onDelete(plan);
    } catch (err) {
      console.error(err);
      setError(err?.message || 'Failed to delete plan. Please try again.');
      setDeleting(false);
    }
  };

  const handleOfficialDurationWeeksChange = (value) => {
    const currentWeeks = Number(officialForm.durationWeeks) || 1;
    const requestedWeeks = Number(value);

    if (!Number.isInteger(requestedWeeks) || requestedWeeks <= 0) {
      setOfficialForm((prev) => ({ ...prev, durationWeeks: value }));
      return;
    }

    const { sessions: resizedSessions, removedSessions } = resizeOfficialSessions(officialSessions, requestedWeeks);
    if (
      requestedWeeks < currentWeeks &&
      officialSessionsNeedTruncationConfirm(removedSessions) &&
      !window.confirm(buildOfficialDurationReductionWarning(currentWeeks, requestedWeeks))
    ) {
      return;
    }

    setOfficialSessions(resizedSessions);
    setOfficialForm((prev) => ({ ...prev, durationWeeks: value }));
  };

  const summary = (
    <div className="wwpdn-summary">
      <div className="wwpdn-summary__media">
        {isValidImageUrl(plan.imageUrl) ? (
          <img src={plan.imageUrl} alt={plan.title || plan.name || 'Plan'} />
        ) : (
          <div className="wwpdn-summary__fallback">No image</div>
        )}
      </div>
      <div className="wwpdn-summary__content">
        <div className="wwpdn-summary__title">{plan.title || plan.name || 'Unnamed Plan'}</div>
        <div className="wwpdn-summary__meta">
          <Badge tone={sourceTone(plan)}>{sourceLabel(plan)}</Badge>
          <Badge tone={levelTone(plan.level)}>{plan.level || 'Beginner'}</Badge>
          <Badge tone="brand">{plan.type || plan.category || 'General'}</Badge>
          <Badge tone={isActive ? 'success' : 'danger'}>{isActive ? 'Active' : 'Inactive'}</Badge>
          {!isCustom && isFeatured ? <Badge tone="warning">Featured</Badge> : null}
        </div>
      </div>
    </div>
  );

  const scheduleSection = (
    <section className="wwa-detail-section">
      <div className="wwa-detail-section__title">Training Schedule</div>
      <div className="wwpdn-schedule">
        {sessions.length > 0 ? sessions.map((session, index) => <SessionCard key={`${plan.id}-session-${index}`} session={session} index={index} />) : <div className="wwa-help-text">No session data available.</div>}
      </div>
    </section>
  );

  return (
    <>
      <PlanDetailStyles />
      <DetailDrawer
        title="Plan"
        width={isEditMode ? 'wide' : 'default'}
        viewportLocked
        open={Boolean(plan)}
        onClose={onClose}
        actions={
          !isEditMode && canEdit ? (
            <button type="button" className="wwa-btn wwa-btn-secondary" onClick={isCustom ? startEdit : startEditOfficial}>
              <Pencil aria-hidden="true" size={16} strokeWidth={2} />
              Edit
            </button>
          ) : null
        }
        summary={summary}
        footer={
          isEditing ? (
            <div className="wwpdn-footer">
              {canDelete ? (
                <button type="button" className="wwa-btn wwa-btn-danger" onClick={handleDeleteClick} disabled={deleting}>
                  <Trash2 aria-hidden="true" size={16} strokeWidth={2} />
                  {deleting ? 'Deleting...' : 'Delete'}
                </button>
              ) : null}
              <div className="wwpdn-footer__primary">
                <button type="button" className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
                  Cancel
                </button>
                <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
                  {saving ? 'Saving...' : 'Save Changes'}
                </button>
              </div>
            </div>
          ) : isEditingOfficial ? (
            <div className="wwpdn-footer">
              {canDelete ? (
                <button type="button" className="wwa-btn wwa-btn-danger" onClick={handleDeleteClick} disabled={deleting}>
                  <Trash2 aria-hidden="true" size={16} strokeWidth={2} />
                  {deleting ? 'Deleting...' : 'Delete'}
                </button>
              ) : null}
              <div className="wwpdn-footer__primary">
                <button type="button" className="wwa-btn wwa-btn-secondary" onClick={cancelEditOfficial} disabled={officialSaving}>
                  Cancel
                </button>
                <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleSaveOfficial} disabled={officialSaving}>
                  {officialSaving ? 'Saving...' : 'Save Changes'}
                </button>
              </div>
            </div>
          ) : (
            <div className="wwpdn-footer">
              {canDelete ? (
                <button type="button" className="wwa-btn wwa-btn-danger" onClick={handleDeleteClick} disabled={deleting}>
                  <Trash2 aria-hidden="true" size={16} strokeWidth={2} />
                  {deleting ? 'Deleting...' : 'Delete'}
                </button>
              ) : null}
            </div>
          )
        }
      >
        {(successMsg || error) ? (
          <div className="wwpdn-message-stack">
            {successMsg ? (
              <div className="wwa-status-pill">
                <span className="wwa-status-dot" />
                {successMsg}
              </div>
            ) : null}
            {error ? <div className="wwa-alert-error">{error}</div> : null}
          </div>
        ) : null}

        {isEditing ? (
          <div className="wwpdn-form">
            <FormSection title="Basic Information" columns={2}>
              <FormField label="Plan Name" labelFor="custom-plan-name" required>
                <input
                  id="custom-plan-name"
                  className="wwa-input"
                  value={form.name}
                  onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
                />
              </FormField>
              <FormField label="Days per Week" labelFor="custom-plan-days" required>
                <input
                  id="custom-plan-days"
                  type="number"
                  min="1"
                  className="wwa-input"
                  value={form.daysPerWeek}
                  onChange={(event) => setForm((prev) => ({ ...prev, daysPerWeek: event.target.value }))}
                />
              </FormField>
              <FormField label="Description" labelFor="custom-plan-description" fullWidth>
                <input
                  id="custom-plan-description"
                  className="wwa-input"
                  value={form.description}
                  onChange={(event) => setForm((prev) => ({ ...prev, description: event.target.value }))}
                />
              </FormField>
            </FormSection>

            <FormSection title="Training Schedule" columns={1}>
              <PlanSessionsEditor
                sessions={customSessions}
                onChange={setCustomSessions}
                exerciseCatalog={exerciseCatalog || []}
                mode="custom"
                planType={plan.type}
              />
            </FormSection>
          </div>
        ) : isEditingOfficial ? (
          <div className="wwpdn-form">
            <FormSection title="Basic Information" columns={2}>
              <FormField label="Plan Name" labelFor="official-plan-name" required>
                <input
                  id="official-plan-name"
                  className="wwa-input"
                  value={officialForm.name}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, name: event.target.value }))}
                />
              </FormField>
              <SelectField
                id="official-plan-level"
                label="Level"
                value={officialForm.level}
                onChange={(event) =>
                  setOfficialForm((prev) => ({
                    ...prev,
                    level: event.target.value,
                    matchLevel: event.target.value,
                  }))
                }
                options={levelOptions || [officialForm.level]}
              />
              <SelectField
                id="official-plan-type"
                label="Type"
                value={officialForm.type}
                onChange={(event) =>
                  setOfficialForm((prev) => ({
                    ...prev,
                    type: event.target.value,
                  }))
                }
                options={typeOptions || [officialForm.type]}
              />
              <FormField label="Days per Week" labelFor="official-plan-days" required>
                <input
                  id="official-plan-days"
                  type="number"
                  min="1"
                  className="wwa-input"
                  value={officialForm.daysPerWeek}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, daysPerWeek: event.target.value }))}
                />
              </FormField>
              <FormField label="Duration (weeks)" labelFor="official-plan-duration" required>
                <input
                  id="official-plan-duration"
                  type="number"
                  min="1"
                  className="wwa-input"
                  value={officialForm.durationWeeks}
                  onChange={(event) => handleOfficialDurationWeeksChange(event.target.value)}
                />
              </FormField>
              <FormField label="Status" labelFor="official-plan-status" fullWidth>
                <label id="official-plan-status" className="wwa-toggle-inline">
                  <input
                    type="checkbox"
                    checked={officialForm.isActive}
                    onChange={(event) => setOfficialForm((prev) => ({ ...prev, isActive: event.target.checked }))}
                  />
                  <span>Active (visible to users)</span>
                </label>
              </FormField>
              <FormField label="Featured Plan" labelFor="official-plan-featured" fullWidth>
                <label id="official-plan-featured" className="wwa-toggle-inline">
                  <input
                    type="checkbox"
                    checked={officialForm.featured}
                    onChange={(event) => setOfficialForm((prev) => ({ ...prev, featured: event.target.checked }))}
                  />
                  <span>Highlight this official plan in featured placements</span>
                </label>
              </FormField>
            </FormSection>

            <FormSection title="Plan Matching" columns={2}>
              <FormField label="Match Sport" labelFor="official-plan-match-sport">
                <input
                  id="official-plan-match-sport"
                  className="wwa-input"
                  value={deriveOfficialMatchSport(officialForm.type)}
                  readOnly
                  disabled
                />
              </FormField>
              <FormField label="Match Level" labelFor="official-plan-match-level">
                <input
                  id="official-plan-match-level"
                  className="wwa-input"
                  value={officialForm.matchLevel}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, matchLevel: event.target.value }))}
                />
              </FormField>
              <FormField label="Goals" labelFor="official-plan-goals">
                <input
                  id="official-plan-goals"
                  className="wwa-input"
                  value={officialForm.goals}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, goals: event.target.value }))}
                  placeholder="Comma-separated, e.g. Build Muscle, Build Strength"
                />
              </FormField>
              <FormField label="Equipment" labelFor="official-plan-equipment">
                <input
                  id="official-plan-equipment"
                  className="wwa-input"
                  value={officialForm.equipment}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, equipment: event.target.value }))}
                  placeholder="Comma-separated, e.g. Barbell, Dumbbells, Bench"
                />
              </FormField>
              <FormField label="Match Goals" labelFor="official-plan-match-goals" fullWidth>
                <input
                  id="official-plan-match-goals"
                  className="wwa-input"
                  value={officialForm.matchGoals}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, matchGoals: event.target.value }))}
                  placeholder="Comma-separated — feeds the Plan Match algorithm"
                />
              </FormField>
            </FormSection>

            <FormSection title="Presentation" columns={2}>
              <FormField label="Description" labelFor="official-plan-description" fullWidth>
                <input
                  id="official-plan-description"
                  className="wwa-input"
                  value={officialForm.description}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, description: event.target.value }))}
                />
              </FormField>
              <FormField label="Image URL" labelFor="official-plan-image">
                <input
                  id="official-plan-image"
                  className="wwa-input"
                  value={officialForm.imageUrl}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, imageUrl: event.target.value }))}
                  placeholder="https://… (optional)"
                />
              </FormField>
            </FormSection>

            <FormSection title="Designed By" description="Optional plan attribution shown to users." columns={2}>
              <FormField label="Name" labelFor="official-plan-designer-name">
                <input
                  id="official-plan-designer-name"
                  className="wwa-input"
                  value={officialForm.designedByName}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, designedByName: event.target.value }))}
                />
              </FormField>
              <FormField label="Title" labelFor="official-plan-designer-title">
                <input
                  id="official-plan-designer-title"
                  className="wwa-input"
                  value={officialForm.designedByTitle}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, designedByTitle: event.target.value }))}
                />
              </FormField>
              <FormField label="Credential" labelFor="official-plan-designer-credential">
                <input
                  id="official-plan-designer-credential"
                  className="wwa-input"
                  value={officialForm.designedByCredential}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, designedByCredential: event.target.value }))}
                />
              </FormField>
              <FormField label="Quote" labelFor="official-plan-designer-quote" fullWidth>
                <input
                  id="official-plan-designer-quote"
                  className="wwa-input"
                  value={officialForm.designedByQuote}
                  onChange={(event) => setOfficialForm((prev) => ({ ...prev, designedByQuote: event.target.value }))}
                />
              </FormField>
            </FormSection>

            <FormSection title="Training Schedule" description="Official plans are grouped into full weeks and must repeat the weekly workout-day count." columns={1}>
              <PlanSessionsEditor
                sessions={officialSessions}
                onChange={setOfficialSessions}
                exerciseCatalog={exerciseCatalog || []}
                mode="official"
                planType={officialForm.type}
              />
            </FormSection>
          </div>
        ) : (
          <>
            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Overview</div>
              <DetailRow label="Description" value={plan.description || undefined} multiline />
              <DetailRow label="Creator" value={creatorLabel} />
              <DetailRow label="Creator UID" value={plan.createdBy || undefined} />
              <DetailRow label="Duration" value={plan.durationWeeks ? `${plan.durationWeeks} weeks` : undefined} />
              <DetailRow label="Days per Week" value={plan.daysPerWeek ?? undefined} />
              {!isCustom ? <DetailRow label="Featured" value={isFeatured ? 'Yes' : 'No'} /> : null}
              <DetailRow label="Equipment" value={formatEquipment(plan.equipment) || undefined} />
              <ListRow label="Goals" values={Array.isArray(plan.goals) ? plan.goals.filter(Boolean) : parseCommaList(plan.goals)} />
              <DetailRow label="Created" value={plan.createdAt ? formatDate(plan.createdAt) : undefined} />
              <DetailRow label="Updated" value={plan.updatedAt ? formatDate(plan.updatedAt) : undefined} />
            </section>

            {(plan.matchSport || plan.matchLevel || (Array.isArray(plan.matchGoals) && plan.matchGoals.length > 0)) ? (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Matching</div>
                <DetailRow label="Match Sport" value={!isCustom ? deriveOfficialMatchSport(plan.type) : plan.matchSport || undefined} />
                <DetailRow label="Match Level" value={plan.matchLevel || undefined} />
                <ListRow label="Match Goals" values={Array.isArray(plan.matchGoals) ? plan.matchGoals.filter(Boolean) : parseCommaList(plan.matchGoals)} />
              </section>
            ) : null}

            {designedBy && Object.values(designedBy).some(Boolean) ? (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Designed By</div>
                <DetailRow label="Name" value={designedBy.name || undefined} />
                <DetailRow label="Title" value={designedBy.title || undefined} />
                <DetailRow label="Credential" value={designedBy.credential || undefined} />
                {designedBy.quote ? <div className="wwpdn-designer-quote">“{designedBy.quote}”</div> : null}
              </section>
            ) : null}

            {scheduleSection}
          </>
        )}
      </DetailDrawer>
    </>
  );
}

export default PlanDetailPanel;
