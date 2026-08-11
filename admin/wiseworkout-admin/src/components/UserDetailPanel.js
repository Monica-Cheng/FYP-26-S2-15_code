import React, { useEffect, useState } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import { Pencil, ShieldCheck, ShieldOff, Trash2 } from 'lucide-react';
import Badge from './ui/Badge';
import ToggleSwitch from './ui/ToggleSwitch';
import DetailDrawer from './ui/DetailDrawer';
import FormSection from './ui/FormSection';
import FormField from './ui/FormField';
import SelectField from './ui/SelectField';
import ModalDialog from './ui/ModalDialog';
import { formatEquipment } from '../utils/formatUtils';

function UserDetailPanelStyles() {
  return (
    <style>{`
      .wwudp-summary {
        display: flex;
        align-items: flex-start;
        gap: 14px;
      }
      .wwudp-summary__content {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .wwudp-summary__title {
        font-size: var(--ww-type-page-title-size);
        font-weight: var(--ww-type-page-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.1;
      }
      .wwudp-summary__meta {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwudp-message-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwudp-message-stack .wwa-status-pill,
      .wwudp-message-stack .wwa-alert-error {
        margin: 0;
      }
      .wwudp-detail-text {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
        white-space: pre-wrap;
      }
      .wwudp-reminder-fields {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }
      .wwudp-reminder-fields .wwa-input {
        width: 72px;
      }
      .wwudp-help-text {
        font-size: 11px;
        color: #b5b8c0;
        margin-top: -10px;
      }
      .wwudp-plan-controls {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwudp-setting {
        display: flex;
        flex-direction: column;
        gap: 12px;
        padding: 14px;
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        background: color-mix(in srgb, var(--ww-elevated) 50%, var(--ww-card));
      }
      .wwudp-setting__top {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 16px;
        flex-wrap: wrap;
      }
      .wwudp-setting__actions {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwudp-setting__duration {
        display: flex;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwudp-setting__counter {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .wwudp-setting__counter-value {
        min-width: 56px;
        text-align: center;
        font-size: 14px;
        font-weight: 700;
        color: var(--ww-text);
      }
      .wwudp-footer {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      @media (max-width: 720px) {
        .wwudp-summary {
          flex-direction: column;
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
      {multiline ? <div className="wwudp-detail-text">{value}</div> : <span className="wwa-detail-value">{value}</span>}
    </div>
  );
}

const monoStyle = { fontFamily: 'Consolas, Menlo, monospace', fontSize: '12px' };

const GOAL_OPTIONS = [
  { value: '', label: 'Not set' },
  { value: 'Build Muscle', label: 'Build Muscle' },
  { value: 'Improve Endurance', label: 'Improve Endurance' },
  { value: 'Lose Weight', label: 'Lose Weight' },
  { value: 'Build Strength', label: 'Build Strength' },
];

const DEFAULT_BREAK_DAYS = 3;
const MIN_BREAK_DAYS = 1;
const MAX_BREAK_DAYS = 14;

const toDateStr = (date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
};

const parseDateStr = (dateStr) => {
  if (!dateStr) return null;
  const [y, m, d] = dateStr.split('-').map(Number);
  if (!y || !m || !d) return null;
  return new Date(y, m - 1, d);
};

const remainingDays = (endDateStr) => {
  const end = parseDateStr(endDateStr);
  if (!end) return null;
  const today = new Date(toDateStr(new Date()));
  return Math.max(0, Math.round((end - today) / (1000 * 60 * 60 * 24)));
};

const formatReminderTime = (hour, minute) => {
  if (hour === undefined || hour === null || minute === undefined || minute === null) return undefined;
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
};

const emptyPlanConfirmState = { type: null, error: '', saving: false };

function UserDetailPanel({ user, onClose, onSave, onSuspend, onReactivate, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const userId = user ? user.id : null;
  const trackedPlanId = user ? user.trackedPlanId : null;
  const [planProgress, setPlanProgress] = useState(null);
  const [planLoading, setPlanLoading] = useState(false);
  const [planActionError, setPlanActionError] = useState('');
  const [savingBreakMode, setSavingBreakMode] = useState(false);
  const [savingCompress, setSavingCompress] = useState(false);
  const [breakDaysInput, setBreakDaysInput] = useState(DEFAULT_BREAK_DAYS);
  const [planConfirmState, setPlanConfirmState] = useState(emptyPlanConfirmState);

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    setBreakDaysInput(DEFAULT_BREAK_DAYS);
    setPlanConfirmState(emptyPlanConfirmState);
  }, [userId]);

  useEffect(() => {
    let cancelled = false;

    const loadPlanProgress = async () => {
      setPlanActionError('');

      if (!userId || !trackedPlanId) {
        setPlanProgress(null);
        setPlanLoading(false);
        return;
      }

      setPlanLoading(true);

      try {
        const adminGetUserPlanProgress = httpsCallable(functions, 'adminGetUserPlanProgress');
        const result = await adminGetUserPlanProgress({
          uid: userId,
          planId: trackedPlanId,
        });

        if (cancelled) return;

        setPlanProgress(result.data.exists ? result.data.progress : null);
      } catch (err) {
        console.error(err);
        if (!cancelled) {
          setPlanProgress(null);
          setPlanActionError(err.message || 'Failed to load the user plan status.');
        }
      } finally {
        if (!cancelled) {
          setPlanLoading(false);
        }
      }
    };

    loadPlanProgress();

    return () => {
      cancelled = true;
    };
  }, [userId, trackedPlanId]);

  if (!user) return null;

  const currentDayIndex = (planProgress && planProgress.currentDayIndex) || 1;
  const compressedDays = Array.isArray(planProgress?.compressedDays) ? planProgress.compressedDays : [];
  const isCurrentDayCompressed = compressedDays.includes(currentDayIndex);

  const runToggleBreakMode = async () => {
    if (!userId || !trackedPlanId) return;

    const currentlyActive = planProgress?.breakModeActive === true;
    const newActiveState = !currentlyActive;

    setSavingBreakMode(true);
    setPlanActionError('');

    try {
      const adminSetUserBreakMode = httpsCallable(functions, 'adminSetUserBreakMode');
      const days = Math.min(MAX_BREAK_DAYS, Math.max(MIN_BREAK_DAYS, Number(breakDaysInput) || DEFAULT_BREAK_DAYS));

      const result = await adminSetUserBreakMode({
        uid: userId,
        planId: trackedPlanId,
        active: newActiveState,
        days: newActiveState ? days : null,
      });

      setPlanProgress(result.data.progress);
    } catch (err) {
      console.error(err);
      setPlanActionError(err.message || 'Failed to update break mode. Please try again.');
    } finally {
      setSavingBreakMode(false);
    }
  };

  const runToggleCompress = async () => {
    if (!userId || !trackedPlanId) return;

    const newCompressedState = !isCurrentDayCompressed;

    setSavingCompress(true);
    setPlanActionError('');

    try {
      const adminSetUserCompressedDay = httpsCallable(functions, 'adminSetUserCompressedDay');

      const result = await adminSetUserCompressedDay({
        uid: userId,
        planId: trackedPlanId,
        compressed: newCompressedState,
      });

      setPlanProgress((prev) => ({
        ...(prev || {}),
        currentDayIndex: result.data.currentDayIndex,
        compressedDays: result.data.compressedDays,
      }));
    } catch (err) {
      console.error(err);
      setPlanActionError(err.message || 'Failed to update compress control. Please try again.');
    } finally {
      setSavingCompress(false);
    }
  };

  const handleToggleBreakMode = () => {
    if (!userId || !trackedPlanId) return;
    setPlanConfirmState({ type: 'breakMode', error: '', saving: false });
  };

  const handleToggleCompress = () => {
    if (!userId || !trackedPlanId) return;
    setPlanConfirmState({ type: 'compress', error: '', saving: false });
  };

  const closePlanConfirmModal = () => {
    if (planConfirmState.saving) return;
    setPlanConfirmState(emptyPlanConfirmState);
  };

  const submitPlanConfirmModal = async () => {
    setPlanConfirmState((prev) => ({ ...prev, saving: true, error: '' }));

    try {
      if (planConfirmState.type === 'breakMode') {
        await runToggleBreakMode();
      } else if (planConfirmState.type === 'compress') {
        await runToggleCompress();
      }

      setPlanConfirmState(emptyPlanConfirmState);
    } catch (err) {
      console.error(err);
      setPlanConfirmState((prev) => ({
        ...prev,
        saving: false,
        error: err?.message || 'Failed to apply the plan change.',
      }));
    }
  };

  const startEdit = () => {
    setForm({
      displayName: user.displayName || '',
      username: user.username || '',
      level: user.level || 1,
      isPremium: !!user.isPremium,
      planMatchGoal: user.planMatchGoal || '',
      hometown: user.hometown || '',
      bio: user.bio || '',
      notificationsEnabled: user.notificationsEnabled !== false,
      workoutReminders: user.workoutReminders !== false,
      streakAlerts: user.streakAlerts !== false,
      wiseCoachMessages: user.wiseCoachMessages !== false,
      reminderHour: user.reminderHour ?? 7,
      reminderMinute: user.reminderMinute ?? 0,
    });
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
    if (!form.displayName.trim()) {
      setError('Display name cannot be empty.');
      return;
    }

    const changes = {};
    const trimmedName = form.displayName.trim();
    if (trimmedName !== (user.displayName || '')) changes.displayName = trimmedName;

    const trimmedUsername = form.username.trim();
    if (trimmedUsername !== (user.username || '')) changes.username = trimmedUsername;

    const newLevel = Number(form.level) || 1;
    if (newLevel !== (user.level || 1)) changes.level = newLevel;

    if (form.isPremium !== !!user.isPremium) changes.isPremium = form.isPremium;
    if (form.planMatchGoal !== (user.planMatchGoal || '')) changes.planMatchGoal = form.planMatchGoal;

    const trimmedHometown = form.hometown.trim();
    if (trimmedHometown !== (user.hometown || '')) changes.hometown = trimmedHometown;

    const trimmedBio = form.bio.trim();
    if (trimmedBio !== (user.bio || '')) changes.bio = trimmedBio;

    const currentNotif = user.notificationsEnabled !== false;
    if (form.notificationsEnabled !== currentNotif) changes.notificationsEnabled = form.notificationsEnabled;

    const currentWorkoutReminders = user.workoutReminders !== false;
    if (form.workoutReminders !== currentWorkoutReminders) changes.workoutReminders = form.workoutReminders;

    const currentStreakAlerts = user.streakAlerts !== false;
    if (form.streakAlerts !== currentStreakAlerts) changes.streakAlerts = form.streakAlerts;

    const currentWiseCoach = user.wiseCoachMessages !== false;
    if (form.wiseCoachMessages !== currentWiseCoach) changes.wiseCoachMessages = form.wiseCoachMessages;

    const newHour = Math.min(23, Math.max(0, Number(form.reminderHour) || 0));
    const currentHour = user.reminderHour ?? 7;
    if (newHour !== currentHour) changes.reminderHour = newHour;

    const newMinute = Math.min(59, Math.max(0, Number(form.reminderMinute) || 0));
    const currentMinute = user.reminderMinute ?? 0;
    if (newMinute !== currentMinute) changes.reminderMinute = newMinute;

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');
    try {
      await onSave(user.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('User profile updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setError('Failed to update user. Please try again.');
    }
    setSaving(false);
  };

  const initialSource = isEditing ? form.displayName : (user.displayName || user.username);
  const initial = (initialSource || '?').trim().charAt(0).toUpperCase();
  const savedPlansCount = Array.isArray(user.savedPlanIds) ? user.savedPlanIds.length : undefined;
  const equipmentLabel = formatEquipment(user.planMatchEquipment);
  const canSuspend = user.accountStatus !== 'suspended' && typeof onSuspend === 'function';
  const canReactivate = user.accountStatus === 'suspended' && typeof onReactivate === 'function';
  const canDelete = typeof onDelete === 'function';

  const summary = (
    <div className="wwudp-summary">
      <div className="wwa-avatar">{initial}</div>
      <div className="wwudp-summary__content">
        <div className="wwudp-summary__title">{user.displayName || user.username || 'Unnamed user'}</div>
        <div className="wwudp-summary__meta">
          <Badge tone="neutral">Level {user.level || 1}</Badge>
          <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
            {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
          </Badge>
          {user.isPremium ? <Badge tone="brand">Premium</Badge> : null}
        </div>
      </div>
    </div>
  );

  return (
    <>
      <UserDetailPanelStyles />
      <DetailDrawer
        title="User"
        open={Boolean(user)}
        onClose={onClose}
        viewportLocked
        actions={
          !isEditing ? (
            <>
              {canSuspend ? (
                <button type="button" className="wwa-btn wwa-btn-danger" onClick={onSuspend}>
                  <ShieldOff aria-hidden="true" size={16} strokeWidth={2} />
                  Suspend
                </button>
              ) : null}
              {canReactivate ? (
                <button type="button" className="wwa-btn wwa-btn-primary" onClick={onReactivate}>
                  <ShieldCheck aria-hidden="true" size={16} strokeWidth={2} />
                  Reinstate
                </button>
              ) : null}
              {canDelete ? (
                <button type="button" className="wwa-btn wwa-btn-danger" onClick={onDelete}>
                  <Trash2 aria-hidden="true" size={16} strokeWidth={2} />
                  Delete
                </button>
              ) : null}
              <button type="button" className="wwa-btn wwa-btn-secondary" onClick={startEdit}>
                <Pencil aria-hidden="true" size={16} strokeWidth={2} />
                Edit
              </button>
            </>
          ) : null
        }
        summary={summary}
        footer={
          isEditing ? (
            <div className="wwudp-footer">
              <button type="button" className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
                Cancel
              </button>
              <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          ) : null
        }
      >
        {(successMsg || error) ? (
          <div className="wwudp-message-stack">
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
          <>
            <FormSection title="Account" columns={2}>
              <FormField label="Display Name" labelFor="user-display-name" required>
                <input
                  id="user-display-name"
                  className="wwa-input"
                  value={form.displayName}
                  onChange={(event) => setForm((prev) => ({ ...prev, displayName: event.target.value }))}
                />
              </FormField>

              <FormField label="Account Level" labelFor="user-level">
                <input
                  id="user-level"
                  type="number"
                  min="1"
                  className="wwa-input"
                  value={form.level}
                  onChange={(event) => setForm((prev) => ({ ...prev, level: event.target.value }))}
                />
              </FormField>

              <FormField label="Account Status" labelFor="user-status-note" helpText="Managed via Suspend / Reinstate.">
                <div id="user-status-note">
                  <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
                    {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
                  </Badge>
                </div>
              </FormField>
            </FormSection>

            <div className="wwudp-help-text">
              Level is normally recalculated automatically as the user earns XP.
            </div>

            <FormSection title="Subscription" columns={1}>
              <FormField label="Premium Status" labelFor="user-premium-toggle">
                <div id="user-premium-toggle" className="wwa-setting-row">
                  <div>
                    <div className="wwa-setting-label">{form.isPremium ? 'Premium' : 'Free'}</div>
                    <div className="wwa-setting-sub">Preserves the existing premium update behaviour.</div>
                  </div>
                  <ToggleSwitch
                    checked={form.isPremium}
                    onChange={(event) => setForm((prev) => ({ ...prev, isPremium: event.target.checked }))}
                  />
                </div>
              </FormField>
            </FormSection>

            <FormSection title="Fitness Profile" columns={2}>
              <FormField label="Username" labelFor="user-username">
                <input
                  id="user-username"
                  className="wwa-input"
                  value={form.username}
                  onChange={(event) => setForm((prev) => ({ ...prev, username: event.target.value }))}
                  placeholder="username"
                />
              </FormField>

              <SelectField
                id="user-goal"
                label="Primary Goal"
                value={form.planMatchGoal}
                onChange={(event) => setForm((prev) => ({ ...prev, planMatchGoal: event.target.value }))}
                options={GOAL_OPTIONS}
              />

              <FormField label="Hometown" labelFor="user-hometown">
                <input
                  id="user-hometown"
                  className="wwa-input"
                  value={form.hometown}
                  onChange={(event) => setForm((prev) => ({ ...prev, hometown: event.target.value }))}
                  placeholder="Hometown"
                />
              </FormField>

              <FormField label="Bio" labelFor="user-bio" fullWidth>
                <textarea
                  id="user-bio"
                  className="wwa-input"
                  style={{ resize: 'vertical', fontFamily: 'inherit' }}
                  rows={3}
                  value={form.bio}
                  onChange={(event) => setForm((prev) => ({ ...prev, bio: event.target.value }))}
                  placeholder="Bio"
                />
              </FormField>
            </FormSection>

            <FormSection title="Preferences" columns={1}>
              {[
                { key: 'notificationsEnabled', label: 'Notifications Enabled' },
                { key: 'workoutReminders', label: 'Workout Reminders' },
                { key: 'streakAlerts', label: 'Streak Alerts' },
                { key: 'wiseCoachMessages', label: 'Wise Coach Messages' },
              ].map(({ key, label }) => (
                <FormField key={key} label={label} labelFor={`pref-${key}`}>
                  <div id={`pref-${key}`} className="wwa-setting-row">
                    <div className="wwa-setting-sub">{form[key] ? 'Enabled' : 'Disabled'}</div>
                    <ToggleSwitch
                      checked={form[key]}
                      onChange={(event) => setForm((prev) => ({ ...prev, [key]: event.target.checked }))}
                    />
                  </div>
                </FormField>
              ))}

              <FormField label="Reminder Time" labelFor="reminder-hour">
                <div className="wwudp-reminder-fields">
                  <input
                    id="reminder-hour"
                    type="number"
                    min="0"
                    max="23"
                    className="wwa-input wwa-input-sm"
                    value={form.reminderHour}
                    onChange={(event) => setForm((prev) => ({ ...prev, reminderHour: event.target.value }))}
                  />
                  <span>:</span>
                  <input
                    id="reminder-minute"
                    type="number"
                    min="0"
                    max="59"
                    className="wwa-input wwa-input-sm"
                    value={form.reminderMinute}
                    onChange={(event) => setForm((prev) => ({ ...prev, reminderMinute: event.target.value }))}
                  />
                </div>
              </FormField>
            </FormSection>
          </>
        ) : (
          <>
            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Account</div>
              <DetailRow label="User ID" value={<span style={monoStyle}>{user.id}</span>} />
              <DetailRow label="Username" value={user.username || '—'} />
              <DetailRow label="Email" value={user.email} />
              <DetailRow
                label="Onboarding Status"
                value={
                  <Badge tone={user.onboardingComplete ? 'success' : 'danger'}>
                    {user.onboardingComplete ? 'Complete' : 'Incomplete'}
                  </Badge>
                }
              />
              <DetailRow
                label="Account Status"
                value={
                  <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
                    {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
                  </Badge>
                }
              />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Health & Subscription</div>
              <DetailRow
                label="Health Connected"
                value={
                  <Badge tone={user.healthConnected ? 'success' : 'neutral'}>
                    {user.healthConnected ? 'Connected' : 'Not connected'}
                  </Badge>
                }
              />
              <DetailRow
                label="Wearable Connected"
                value={
                  <Badge tone={user.wearableConnected ? 'success' : 'neutral'}>
                    {user.wearableConnected ? 'Connected' : 'Not connected'}
                  </Badge>
                }
              />
              <DetailRow
                label="Subscription"
                value={
                  <Badge tone={user.isPremium ? 'brand' : 'neutral'}>
                    {user.isPremium ? 'Premium' : 'Free'}
                  </Badge>
                }
              />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Fitness Profile</div>
              <DetailRow label="Primary Goal" value={user.planMatchGoal || 'Not set'} />
              <DetailRow label="Hometown" value={user.hometown || '—'} />
              <DetailRow label="Bio" value={user.bio || undefined} multiline />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Plan Information</div>
              <DetailRow label="Plan Match Level" value={user.planMatchLevel} />
              <DetailRow label="Plan Match Sport" value={user.planMatchSport} />
              <DetailRow label="Plan Match Days" value={user.planMatchDays} />
              <DetailRow label="Plan Match Equipment" value={equipmentLabel !== '—' ? equipmentLabel : undefined} />
              <DetailRow label="Tracked Plan" value={user.trackedPlanName} />
              <DetailRow label="Tracked Plan ID" value={user.trackedPlanId ? <span style={monoStyle}>{user.trackedPlanId}</span> : undefined} />
              <DetailRow
                label="Saved Plans"
                value={savedPlansCount !== undefined ? `${savedPlansCount} plan${savedPlansCount === 1 ? '' : 's'}` : undefined}
              />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">XP / Activity</div>
              <DetailRow label="Total XP" value={user.totalXp !== undefined ? `${user.totalXp} XP` : undefined} />
              <DetailRow label="Weekly XP" value={user.weeklyXp !== undefined ? `${user.weeklyXp} XP` : undefined} />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Preferences</div>
              {[
                { key: 'notificationsEnabled', label: 'Notifications Enabled' },
                { key: 'workoutReminders', label: 'Workout Reminders' },
                { key: 'streakAlerts', label: 'Streak Alerts' },
                { key: 'wiseCoachMessages', label: 'Wise Coach Messages' },
              ].map(({ key, label }) => {
                const currentValue = user[key] !== false;
                return (
                  <DetailRow
                    key={key}
                    label={label}
                    value={
                      <Badge tone={currentValue ? 'success' : 'neutral'}>
                        {currentValue ? 'Enabled' : 'Disabled'}
                      </Badge>
                    }
                  />
                );
              })}
              <DetailRow label="Reminder Time" value={formatReminderTime(user.reminderHour, user.reminderMinute) || '—'} />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Plan Controls</div>
              {!trackedPlanId ? (
                <div className="wwa-help-text">
                  No active plan is being tracked — Break Mode and Compress Control are unavailable.
                </div>
              ) : planLoading ? (
                <div className="wwa-help-text">Loading plan status…</div>
              ) : (
                <div className="wwudp-plan-controls">
                  {planActionError ? <div className="wwa-alert-error">{planActionError}</div> : null}

                  <div className="wwudp-setting">
                    <div className="wwudp-setting__top">
                      <div>
                        <div className="wwa-setting-label">Break Mode</div>
                        <div className="wwa-setting-sub">
                          {planProgress?.breakModeActive
                            ? `Paused until ${planProgress.breakEndDate || '—'}`
                            : 'Plan is actively progressing'}
                        </div>
                      </div>
                      <div className="wwudp-setting__actions">
                        <Badge tone={planProgress?.breakModeActive ? 'brand' : 'neutral'}>
                          {planProgress?.breakModeActive ? 'Active' : 'Inactive'}
                        </Badge>
                        <ToggleSwitch
                          checked={!!planProgress?.breakModeActive}
                          onChange={handleToggleBreakMode}
                          disabled={savingBreakMode}
                        />
                      </div>
                    </div>

                    {planProgress?.breakModeActive ? (
                      <>
                        <DetailRow label="Duration" value={planProgress.breakDays ? `${planProgress.breakDays} days` : '—'} />
                        <DetailRow label="Start Date" value={planProgress.breakStartDate || '—'} />
                        <DetailRow label="Resume Date" value={planProgress.breakEndDate || '—'} />
                        <DetailRow
                          label="Remaining"
                          value={planProgress.breakEndDate ? `${remainingDays(planProgress.breakEndDate)} days` : undefined}
                        />
                      </>
                    ) : (
                      <div className="wwudp-setting__duration">
                        <span className="wwa-field-label" style={{ marginBottom: 0 }}>Duration</span>
                        <div className="wwudp-setting__counter">
                          <button
                            type="button"
                            className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                            onClick={() => setBreakDaysInput((days) => Math.max(MIN_BREAK_DAYS, days - 1))}
                            disabled={savingBreakMode || breakDaysInput <= MIN_BREAK_DAYS}
                          >
                            −
                          </button>
                          <span className="wwudp-setting__counter-value">
                            {breakDaysInput} {breakDaysInput === 1 ? 'day' : 'days'}
                          </span>
                          <button
                            type="button"
                            className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                            onClick={() => setBreakDaysInput((days) => Math.min(MAX_BREAK_DAYS, days + 1))}
                            disabled={savingBreakMode || breakDaysInput >= MAX_BREAK_DAYS}
                          >
                            +
                          </button>
                        </div>
                      </div>
                    )}
                  </div>

                  <div className="wwudp-setting">
                    <div className="wwudp-setting__top">
                      <div>
                        <div className="wwa-setting-label">Compress Control</div>
                        <div className="wwa-setting-sub">{`Day ${currentDayIndex} of the tracked plan`}</div>
                      </div>
                      <div className="wwudp-setting__actions">
                        <Badge tone={isCurrentDayCompressed ? 'brand' : 'neutral'}>
                          {isCurrentDayCompressed ? 'Compressed' : 'Full session'}
                        </Badge>
                        <ToggleSwitch
                          checked={isCurrentDayCompressed}
                          onChange={handleToggleCompress}
                          disabled={savingCompress}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </section>
          </>
        )}
      </DetailDrawer>

      <ModalDialog
        open={Boolean(planConfirmState.type)}
        title={planConfirmState.type === 'breakMode' ? 'Break Mode' : 'Compress Control'}
        description={
          planConfirmState.type === 'breakMode'
            ? planProgress?.breakModeActive
              ? 'This will end Break Mode for the tracked plan immediately.'
              : 'This will start Break Mode for the tracked plan using the selected duration.'
            : planConfirmState.type === 'compress'
              ? isCurrentDayCompressed
                ? `This will restore Day ${currentDayIndex} to the full session.`
                : `This will compress Day ${currentDayIndex} of the tracked plan.`
              : undefined
        }
        onClose={closePlanConfirmModal}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closePlanConfirmModal} disabled={planConfirmState.saving}>
              Cancel
            </button>
            <button type="button" className="wwa-btn wwa-btn-primary" onClick={submitPlanConfirmModal} disabled={planConfirmState.saving}>
              {planConfirmState.saving ? 'Saving...' : 'Confirm'}
            </button>
          </>
        }
      >
        {planConfirmState.error ? <div className="wwa-alert-error">{planConfirmState.error}</div> : null}
      </ModalDialog>
    </>
  );
}

export default UserDetailPanel;
