import React, { useState, useEffect } from 'react';
import Badge from './ui/Badge';
import ImageThumb from './ui/ImageThumb';
import { formatDate } from '../utils/dateUtils';
import { formatEquipment } from '../utils/formatUtils';
import { parseCommaList, formatCommaList, buildDesignedBy } from '../utils/planUtils';
import PlanSessionsEditor, {
  buildDefaultSessions, buildAndValidateSessions, sessionsFromPlan,
  buildDefaultCustomSessions, buildAndValidateCustomSessions, customSessionsFromPlan,
} from './PlanSessionsEditor';

const SET_TYPE_LABELS = { W: 'Warmup', N: 'Normal', D: 'Drop Set' };

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

// sets may be an array of {type, kg, reps} maps, a plain integer count from
// older data, or missing entirely — every shape must render safely.
function SetList({ sets }) {
  if (Array.isArray(sets)) {
    if (sets.length === 0) return <span className="wwa-detail-value">No set data</span>;
    return (
      <div className="wwa-set-list">
        {sets.map((s, i) => (
          <span key={i} className="wwa-set-chip">
            {SET_TYPE_LABELS[s?.type] || s?.type || 'Set'} · {s?.kg ?? '—'}kg × {s?.reps ?? '—'}
          </span>
        ))}
      </div>
    );
  }
  if (typeof sets === 'number') {
    return <span className="wwa-detail-value">{sets} sets</span>;
  }
  return <span className="wwa-detail-value">No set data</span>;
}

// Only ever trusts a real `isCardio: true` flag to render the cardio-block
// layout — anything merely cardio-shaped (e.g. muscle: "Cardio" without the
// flag) renders as a normal gym exercise instead of being guessed at.
function ExerciseRow({ exercise }) {
  if (exercise && exercise.isCardio === true) {
    return (
      <div className="wwa-exercise-row">
        <div className="wwa-exercise-name">
          {exercise.name || 'Cardio block'}
          <Badge tone="brand">Cardio</Badge>
          {exercise.tag && <Badge tone={exercise.tag === 'Primary' ? 'brand' : 'neutral'}>{exercise.tag}</Badge>}
        </div>
        <div className="wwa-exercise-meta">
          {exercise.cardioActivity || '—'}
          {exercise.cardioMinutes !== undefined && exercise.cardioMinutes !== null ? ` · ${exercise.cardioMinutes} min` : ''}
        </div>
      </div>
    );
  }

  const tag = exercise.tag || '';
  return (
    <div className="wwa-exercise-row">
      <div className="wwa-exercise-name">
        {exercise.name || 'Unnamed exercise'}
        {tag && <Badge tone={tag === 'Primary' ? 'brand' : 'neutral'}>{tag}</Badge>}
      </div>
      <div className="wwa-exercise-meta">
        {exercise.muscle || '—'}
        {exercise.restTime !== undefined && exercise.restTime !== null ? ` · Rest ${exercise.restTime}s` : ''}
      </div>
      {exercise.note && <div className="wwa-exercise-note">{exercise.note}</div>}
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
    <div className="wwa-session-card">
      <div className="wwa-session-header">
        <span>Day {dayNumber}</span>
        <span>{label}</span>
        {session.type && <Badge tone="neutral">{session.type}</Badge>}
        {session.estimatedMinutes ? <Badge tone="neutral">{session.estimatedMinutes} min</Badge> : null}
        {isRestDay && <Badge tone="neutral">Rest Day</Badge>}
        {!isRestDay && <Badge tone="neutral">{exercises.length} exercise{exercises.length === 1 ? '' : 's'}</Badge>}
      </div>
      {!isRestDay && (
        exercises.length > 0
          ? exercises.map((ex, i) => <ExerciseRow key={i} exercise={ex} />)
          : <div className="wwa-exercise-meta">No exercises recorded for this session.</div>
      )}
    </div>
  );
}

function PlanDetailPanel({ plan, creatorLabel, levelOptions, typeOptions, exerciseCatalog, onClose, onSave, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  // Populated only for custom-plan editing (isEditing && isCustom) — the
  // custom-mode counterpart of officialSessions below, using the same
  // PlanSessionsEditor component in mode="custom".
  const [customSessions, setCustomSessions] = useState([]);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const planId = plan ? plan.id : null;

  // Official-plan editing is a separate state track from the custom-plan
  // `isEditing`/`form` above — kept fully independent so nothing here can
  // change custom-plan edit behavior.
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
  }, [planId]);

  if (!plan) return null;

  const sessions = Array.isArray(plan.sessions) ? plan.sessions : [];
  const isCustom = !!plan.isCustom;
  const isActive = plan.isActive !== false;
  const designedBy = plan.designedBy && typeof plan.designedBy === 'object' ? plan.designedBy : null;

  const startEdit = () => {
    setForm({
      name: plan.name || '',
      description: plan.description || '',
      daysPerWeek: plan.daysPerWeek ?? '',
    });
    setCustomSessions(
      sessions.length > 0 ? customSessionsFromPlan(sessions) : buildDefaultCustomSessions(plan.daysPerWeek)
    );
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  };

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  // Full custom-plan edit, reusing PlanSessionsEditor in mode="custom" (sets
  // stay arrays of {type, kg, reps} — never converted to official-plan
  // integer sets). level ("Custom") and type ("Gym") are intentionally never
  // touched here: updateCustomRoutine in firestore_service.dart — the app's
  // own edit path — never writes them either, so the app itself treats them
  // as fixed once a custom plan is created.
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

    const { sessions: builtSessions, error: sessionsError } = buildAndValidateCustomSessions(customSessions);
    if (sessionsError) { setError(sessionsError); return; }

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

  // Official-plan edit: full form matching Add Plan's fields, reusing the
  // exact same PlanSessionsEditor + buildAndValidateSessions used there so
  // there's only one editor for the official-plan session/exercise shape.
  const startEditOfficial = () => {
    setOfficialForm({
      name: plan.name || '',
      description: plan.description || '',
      level: plan.level || (levelOptions && levelOptions[0]) || 'Beginner',
      type: plan.type || (typeOptions && typeOptions[0]) || 'Gym',
      daysPerWeek: plan.daysPerWeek ?? '',
      durationWeeks: plan.durationWeeks ?? '',
      equipment: formatCommaList(plan.equipment),
      goals: formatCommaList(plan.goals),
      matchGoals: formatCommaList(plan.matchGoals),
      matchSport: plan.matchSport || plan.type || '',
      matchLevel: plan.matchLevel || plan.level || '',
      isActive: plan.isActive !== false,
      imageUrl: plan.imageUrl || '',
      designedByName: designedBy?.name || '',
      designedByTitle: designedBy?.title || '',
      designedByCredential: designedBy?.credential || '',
      designedByQuote: designedBy?.quote || '',
    });
    setOfficialSessions(
      sessions.length > 0 ? sessionsFromPlan(sessions) : buildDefaultSessions(plan.daysPerWeek)
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
    if (!officialForm.name.trim()) { setError('Plan Name cannot be empty.'); return; }
    if (!officialForm.level) { setError('Level is required.'); return; }
    if (!officialForm.type) { setError('Type is required.'); return; }
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

    const { sessions: builtSessions, error: sessionsError } = buildAndValidateSessions(officialSessions, days);
    if (sessionsError) { setError(sessionsError); return; }

    const equipmentList = parseCommaList(officialForm.equipment);
    const goalsList = parseCommaList(officialForm.goals);
    const matchGoalsList = parseCommaList(officialForm.matchGoals);
    const newDesignedBy = buildDesignedBy({
      name: officialForm.designedByName,
      title: officialForm.designedByTitle,
      credential: officialForm.designedByCredential,
      quote: officialForm.designedByQuote,
    });

    // Diff-based, like every other edit in this codebase — untouched fields
    // are never included, so updateDoc's partial write leaves them exactly
    // as they were. isCustom/createdBy/createdAt are never written here.
    const changes = {};
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
    if (officialForm.matchSport !== (plan.matchSport || '')) changes.matchSport = officialForm.matchSport;
    if (officialForm.matchLevel !== (plan.matchLevel || '')) changes.matchLevel = officialForm.matchLevel;
    if (officialForm.isActive !== isActive) changes.isActive = officialForm.isActive;
    if (officialForm.imageUrl.trim() !== (plan.imageUrl || '')) changes.imageUrl = officialForm.imageUrl.trim();
    if (newDesignedBy && JSON.stringify(newDesignedBy) !== JSON.stringify(designedBy || undefined)) {
      changes.designedBy = newDesignedBy;
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
      setError('Failed to update plan. Please try again.');
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
      // On success the parent removes this plan and clears the selection,
      // which unmounts this panel — no further local state update needed.
    } catch (err) {
      console.error(err);
      setError('Failed to delete plan. Please try again.');
      setDeleting(false);
    }
  };

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>Plan Detail</div>
        <button className="wwa-panel-close" onClick={onClose} aria-label="Close plan detail">✕</button>
      </div>

      {successMsg && (
        <div className="wwa-status-pill" style={{ marginBottom: 16 }}>
          <span className="wwa-status-dot" />
          {successMsg}
        </div>
      )}
      {error && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{error}</div>}

      {!isEditing && !isEditingOfficial && plan.imageUrl && (
        <ImageThumb url={plan.imageUrl} size={64} icon="📋" />
      )}

      {isEditing ? (
        <input
          className="wwa-input"
          value={form.name}
          onChange={e => setForm(prev => ({ ...prev, name: e.target.value }))}
          placeholder="Plan name"
          style={{ marginBottom: 8, marginTop: 12, fontSize: 15, fontWeight: 700 }}
        />
      ) : isEditingOfficial ? (
        <input
          className="wwa-input"
          value={officialForm.name}
          onChange={e => setOfficialForm(prev => ({ ...prev, name: e.target.value }))}
          placeholder="Plan name"
          style={{ marginBottom: 8, marginTop: 12, fontSize: 15, fontWeight: 700 }}
        />
      ) : (
        <div style={{ fontSize: '16px', fontWeight: 700, color: '#111827', marginBottom: 8, marginTop: plan.imageUrl ? 10 : 0 }}>
          {plan.title || plan.name || 'Unnamed Plan'}
        </div>
      )}

      <div style={{ display: 'flex', gap: 6, marginBottom: 20, flexWrap: 'wrap' }}>
        <Badge tone={isCustom ? 'brand' : 'neutral'}>{isCustom ? 'Custom' : 'Official/System'}</Badge>
        <Badge tone="neutral">{plan.level || 'Beginner'}</Badge>
        <Badge tone="brand">{plan.type || plan.category || 'General'}</Badge>
        <Badge tone={isActive ? 'success' : 'danger'}>{isActive ? 'Active' : 'Inactive'}</Badge>
      </div>

      {isEditing ? (
        <div className="wwa-form-grid" style={{ marginBottom: 18 }}>
          <div className="wwa-field-full">
            <label className="wwa-field-label">Description</label>
            <input
              className="wwa-input"
              value={form.description}
              onChange={e => setForm(prev => ({ ...prev, description: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Days per Week</label>
            <input
              type="number"
              min="1"
              className="wwa-input"
              value={form.daysPerWeek}
              onChange={e => setForm(prev => ({ ...prev, daysPerWeek: e.target.value }))}
            />
          </div>
        </div>
      ) : isEditingOfficial ? (
        <div className="wwa-form-grid" style={{ marginBottom: 4 }}>
          <div>
            <label className="wwa-field-label">Level</label>
            <select
              className="wwa-select"
              value={officialForm.level}
              onChange={e => setOfficialForm(prev => ({
                ...prev, level: e.target.value, matchLevel: e.target.value,
              }))}
            >
              {(levelOptions || [officialForm.level]).map(l => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
          <div>
            <label className="wwa-field-label">Type</label>
            <select
              className="wwa-select"
              value={officialForm.type}
              onChange={e => setOfficialForm(prev => ({
                ...prev, type: e.target.value, matchSport: e.target.value,
              }))}
            >
              {(typeOptions || [officialForm.type]).map(t => <option key={t} value={t}>{t}</option>)}
            </select>
          </div>
          <div>
            <label className="wwa-field-label">Days per Week</label>
            <input
              type="number"
              min="1"
              className="wwa-input"
              value={officialForm.daysPerWeek}
              onChange={e => setOfficialForm(prev => ({ ...prev, daysPerWeek: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Duration (weeks)</label>
            <input
              type="number"
              min="1"
              className="wwa-input"
              value={officialForm.durationWeeks}
              onChange={e => setOfficialForm(prev => ({ ...prev, durationWeeks: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Equipment</label>
            <input
              className="wwa-input"
              value={officialForm.equipment}
              onChange={e => setOfficialForm(prev => ({ ...prev, equipment: e.target.value }))}
              placeholder="Comma-separated, e.g. Barbell, Dumbbells, Bench"
            />
          </div>
          <div>
            <label className="wwa-field-label">Goals</label>
            <input
              className="wwa-input"
              value={officialForm.goals}
              onChange={e => setOfficialForm(prev => ({ ...prev, goals: e.target.value }))}
              placeholder="Comma-separated, e.g. Build Muscle, Build Strength"
            />
          </div>
          <div>
            <label className="wwa-field-label">Match Sport</label>
            <input
              className="wwa-input"
              value={officialForm.matchSport}
              onChange={e => setOfficialForm(prev => ({ ...prev, matchSport: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Match Level</label>
            <input
              className="wwa-input"
              value={officialForm.matchLevel}
              onChange={e => setOfficialForm(prev => ({ ...prev, matchLevel: e.target.value }))}
            />
          </div>
          <div className="wwa-field-full">
            <label className="wwa-field-label">Match Goals</label>
            <input
              className="wwa-input"
              value={officialForm.matchGoals}
              onChange={e => setOfficialForm(prev => ({ ...prev, matchGoals: e.target.value }))}
              placeholder="Comma-separated — feeds the Plan Match algorithm"
            />
          </div>
          <div className="wwa-field-full">
            <label className="wwa-field-label">Description</label>
            <input
              className="wwa-input"
              value={officialForm.description}
              onChange={e => setOfficialForm(prev => ({ ...prev, description: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Image URL</label>
            <input
              className="wwa-input"
              value={officialForm.imageUrl}
              onChange={e => setOfficialForm(prev => ({ ...prev, imageUrl: e.target.value }))}
              placeholder="https://… (optional)"
            />
          </div>
          <div>
            <label className="wwa-field-label">Status</label>
            <div style={{ paddingTop: 8, display: 'flex', alignItems: 'center', gap: 10 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#374151' }}>
                <input
                  type="checkbox"
                  checked={officialForm.isActive}
                  onChange={e => setOfficialForm(prev => ({ ...prev, isActive: e.target.checked }))}
                />
                Active (visible to users)
              </label>
            </div>
          </div>

          <div className="wwa-field-full" style={{ marginTop: 8 }}>
            <div className="wwa-panel-subtitle" style={{ marginBottom: 4 }}>Designed By (optional)</div>
          </div>
          <div>
            <label className="wwa-field-label">Name</label>
            <input
              className="wwa-input"
              value={officialForm.designedByName}
              onChange={e => setOfficialForm(prev => ({ ...prev, designedByName: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Title</label>
            <input
              className="wwa-input"
              value={officialForm.designedByTitle}
              onChange={e => setOfficialForm(prev => ({ ...prev, designedByTitle: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Credential</label>
            <input
              className="wwa-input"
              value={officialForm.designedByCredential}
              onChange={e => setOfficialForm(prev => ({ ...prev, designedByCredential: e.target.value }))}
            />
          </div>
          <div className="wwa-field-full">
            <label className="wwa-field-label">Quote</label>
            <input
              className="wwa-input"
              value={officialForm.designedByQuote}
              onChange={e => setOfficialForm(prev => ({ ...prev, designedByQuote: e.target.value }))}
            />
          </div>
        </div>
      ) : (
        <div style={{ marginBottom: 20 }}>
          <DetailRow label="Description" value={plan.description || '—'} />
          <DetailRow label="Creator" value={creatorLabel} />
          <DetailRow label="Days per Week" value={plan.daysPerWeek ?? '—'} />
          <DetailRow label="Duration (weeks)" value={plan.durationWeeks ?? undefined} />
          <DetailRow label="Equipment" value={formatEquipment(plan.equipment)} />
          <DetailRow label="Goals" value={formatCommaList(plan.goals) || undefined} />
          <DetailRow label="Match Goals" value={formatCommaList(plan.matchGoals) || undefined} />
          <DetailRow label="Match Sport" value={plan.matchSport || undefined} />
          <DetailRow label="Match Level" value={plan.matchLevel || undefined} />
          {designedBy && (
            <>
              <DetailRow label="Designed By" value={designedBy.name || undefined} />
              <DetailRow label="Designer Title" value={designedBy.title || undefined} />
              <DetailRow label="Designer Credential" value={designedBy.credential || undefined} />
              <DetailRow label="Designer Quote" value={designedBy.quote || undefined} />
            </>
          )}
          <DetailRow label="Created At" value={formatDate(plan.createdAt)} />
          <DetailRow label="Updated At" value={plan.updatedAt ? formatDate(plan.updatedAt) : '—'} />
        </div>
      )}

      {isEditingOfficial && (
        <>
          <div className="wwa-panel-subtitle" style={{ marginTop: 4 }}>Training Sessions (Week Schedule)</div>
          <PlanSessionsEditor
            sessions={officialSessions}
            onChange={setOfficialSessions}
            exerciseCatalog={exerciseCatalog || []}
            mode="official"
          />
        </>
      )}

      {isEditing && (
        <>
          <div className="wwa-panel-subtitle" style={{ marginTop: 4 }}>Training Sessions</div>
          <PlanSessionsEditor
            sessions={customSessions}
            onChange={setCustomSessions}
            exerciseCatalog={exerciseCatalog || []}
            mode="custom"
          />
        </>
      )}

      {isEditing ? (
        <div className="wwa-cell-actions" style={{ marginTop: 16, marginBottom: 20 }}>
          <button className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
          <button className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
            Cancel
          </button>
        </div>
      ) : isEditingOfficial ? (
        <div className="wwa-cell-actions" style={{ marginTop: 16, marginBottom: 20 }}>
          <button className="wwa-btn wwa-btn-primary" onClick={handleSaveOfficial} disabled={officialSaving}>
            {officialSaving ? 'Saving...' : 'Save Changes'}
          </button>
          <button className="wwa-btn wwa-btn-secondary" onClick={cancelEditOfficial} disabled={officialSaving}>
            Cancel
          </button>
        </div>
      ) : (
        <div className="wwa-cell-actions" style={{ marginBottom: 20 }}>
          <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={isCustom ? startEdit : startEditOfficial}>
            Edit
          </button>
          <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={handleDeleteClick} disabled={deleting}>
            {deleting ? 'Deleting...' : 'Delete'}
          </button>
        </div>
      )}

      {!isEditing && !isEditingOfficial && (
        <>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 8 }}>Sessions</div>
          {sessions.length > 0 ? (
            sessions.map((session, i) => <SessionCard key={i} session={session} index={i} />)
          ) : (
            <div className="wwa-detail-value" style={{ color: '#9ca3af' }}>No session data available.</div>
          )}
        </>
      )}
    </div>
  );
}

export default PlanDetailPanel;
