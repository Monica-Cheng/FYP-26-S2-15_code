import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { doc, onSnapshot, updateDoc } from 'firebase/firestore';
import Badge from './ui/Badge';
import ToggleSwitch from './ui/ToggleSwitch';
import { formatEquipment } from '../utils/formatUtils';

// Fields beyond the core identity/status set are only rendered when the
// selected user's document actually has them — most come from onboarding
// steps in the mobile app and are not guaranteed to exist for every user.
function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

const monoStyle = { fontFamily: 'Consolas, Menlo, monospace', fontSize: '12px' };

// Real enum values written by the mobile app's plan-matching flow
// (lib/screens/plans/plan_match_screen.dart's _GoalOption list) — reused as-is
// so admin edits stay compatible with what the app itself writes to
// planMatchGoal. This is a different, Title-Case domain from the old
// onboarding-step "primaryGoal" field this panel previously edited.
const GOAL_OPTIONS = [
  { value: '', label: 'Not set' },
  { value: 'Build Muscle', label: 'Build Muscle' },
  { value: 'Improve Endurance', label: 'Improve Endurance' },
  { value: 'Lose Weight', label: 'Lose Weight' },
  { value: 'Build Strength', label: 'Build Strength' },
];

// Real enum values written by onboarding_step1_screen.dart's preferredUnits field.
const UNITS_OPTIONS = [
  { value: '', label: 'Not set' },
  { value: 'metric', label: 'Metric' },
  { value: 'imperial', label: 'Imperial' },
];
const UNITS_LABELS = { metric: 'Metric', imperial: 'Imperial' };

const DEFAULT_BREAK_DAYS = 3;
// Mirrors the largest preset chip in plan_schedule_screen.dart's break-day
// picker ([1, 2, 3, 5, 7, 14]) — the app itself never offers more than 14.
const MIN_BREAK_DAYS = 1;
const MAX_BREAK_DAYS = 14;

const toDateStr = (date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
};

// breakEndDate/breakStartDate are stored as "YYYY-MM-DD" strings (see
// toDateStr above and plan_schedule_screen.dart's _startBreak) — parsed as
// local dates here so the day-count math lines up with how they were written.
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

// reminderHour/reminderMinute default to 7:00am, matching settings_screen.dart's
// TimeOfDay(hour: 7, minute: 0) default when a user has never saved a reminder time.
const formatReminderTime = (hour, minute) => {
  if (hour === undefined || hour === null || minute === undefined || minute === null) return undefined;
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
};

function UserDetailPanel({ user, onClose, onSave }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const userId = user ? user.id : null;
  const trackedPlanId = user ? user.trackedPlanId : null;

  // Break Mode and Compress Control both live on the tracked plan's
  // planProgress subcollection doc (users/{uid}/planProgress/{planId}) —
  // the same doc the mobile app itself reads and writes — not on the user
  // doc directly.
  const [planProgress, setPlanProgress] = useState(null);
  const [planLoading, setPlanLoading] = useState(false);
  const [planActionError, setPlanActionError] = useState('');
  const [savingBreakMode, setSavingBreakMode] = useState(false);
  const [savingCompress, setSavingCompress] = useState(false);
  const [breakDaysInput, setBreakDaysInput] = useState(DEFAULT_BREAK_DAYS);

  // If the admin views a different user (or the panel is reused), drop any
  // in-progress edit state tied to the previous selection.
  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    setBreakDaysInput(DEFAULT_BREAK_DAYS);
  }, [userId]);

  useEffect(() => {
    setPlanActionError('');
    if (!userId || !trackedPlanId) {
      setPlanProgress(null);
      setPlanLoading(false);
      return undefined;
    }
    setPlanLoading(true);
    const ref = doc(db, 'users', userId, 'planProgress', trackedPlanId);
    const unsubscribe = onSnapshot(ref, snap => {
      setPlanProgress(snap.exists() ? snap.data() : null);
      setPlanLoading(false);
    }, err => {
      console.error(err);
      setPlanLoading(false);
    });
    return unsubscribe;
  }, [userId, trackedPlanId]);

  if (!user) return null;

  const currentDayIndex = (planProgress && planProgress.currentDayIndex) || 1;
  const compressedDays = Array.isArray(planProgress?.compressedDays) ? planProgress.compressedDays : [];
  const isCurrentDayCompressed = compressedDays.includes(currentDayIndex);

  // Mirrors _startBreak/_endBreak in plan_schedule_screen.dart exactly, so
  // the app reads back a break state it already knows how to interpret.
  const handleToggleBreakMode = async () => {
    if (!userId || !trackedPlanId) return;
    setSavingBreakMode(true);
    setPlanActionError('');
    try {
      const ref = doc(db, 'users', userId, 'planProgress', trackedPlanId);
      if (planProgress?.breakModeActive) {
        await updateDoc(ref, {
          breakModeActive: false,
          breakStartDate: null,
          breakEndDate: null,
          breakDays: null,
        });
      } else {
        const days = Math.min(MAX_BREAK_DAYS, Math.max(MIN_BREAK_DAYS, Number(breakDaysInput) || DEFAULT_BREAK_DAYS));
        const today = new Date();
        const endDate = new Date(today);
        endDate.setDate(endDate.getDate() + days);
        await updateDoc(ref, {
          breakModeActive: true,
          breakStartDate: toDateStr(today),
          breakEndDate: toDateStr(endDate),
          breakDays: days,
        });
      }
    } catch (err) {
      console.error(err);
      setPlanActionError('Failed to update break mode. Please try again.');
    }
    setSavingBreakMode(false);
  };

  // Mirrors _showCompressSheet/_restoreDaySession in plan_schedule_screen.dart —
  // adds/removes the current day index from compressedDays, the same list the
  // app reads to decide whether to show the compressed (primary-only) session.
  const handleToggleCompress = async () => {
    if (!userId || !trackedPlanId) return;
    setSavingCompress(true);
    setPlanActionError('');
    try {
      const ref = doc(db, 'users', userId, 'planProgress', trackedPlanId);
      const updated = isCurrentDayCompressed
        ? compressedDays.filter(d => d !== currentDayIndex)
        : [...compressedDays, currentDayIndex];
      await updateDoc(ref, { compressedDays: updated });
    } catch (err) {
      console.error(err);
      setPlanActionError('Failed to update compress control. Please try again.');
    }
    setSavingCompress(false);
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
      preferredUnits: user.preferredUnits || '',
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

  // Only fields that actually changed are included in the update, so saving
  // never overwrites fields this form doesn't manage (savedPlanIds, XP,
  // trackedPlanId/Name, onboardingComplete, healthConnected, wearableConnected, etc.).
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

    if (form.preferredUnits !== (user.preferredUnits || '')) changes.preferredUnits = form.preferredUnits;

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

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>User Detail</div>
        <div style={{ display: 'flex', gap: 8 }}>
          {!isEditing && (
            <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={startEdit}>
              Edit
            </button>
          )}
          <button className="wwa-panel-close" onClick={onClose} aria-label="Close user detail">✕</button>
        </div>
      </div>

      {successMsg && (
        <div className="wwa-status-pill" style={{ marginBottom: 16 }}>
          <span className="wwa-status-dot" />
          {successMsg}
        </div>
      )}
      {error && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{error}</div>}

      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 20 }}>
        <div className="wwa-avatar">{initial}</div>
        <div style={{ flex: 1 }}>
          {isEditing ? (
            <input
              className="wwa-input"
              value={form.displayName}
              onChange={e => setForm(prev => ({ ...prev, displayName: e.target.value }))}
              placeholder="Display name"
            />
          ) : (
            <div style={{ fontSize: '16px', fontWeight: 700, color: '#111827' }}>
              {user.displayName || user.username || 'Unnamed user'}
            </div>
          )}
          {!isEditing && (
            <div style={{ display: 'flex', gap: 6, marginTop: 6, flexWrap: 'wrap' }}>
              <Badge tone="neutral">Level {user.level || 1}</Badge>
              <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
                {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
              </Badge>
            </div>
          )}
        </div>
      </div>

      {isEditing && (
        <div className="wwa-form-grid" style={{ marginBottom: 4 }}>
          <div>
            <label className="wwa-field-label">Account Level</label>
            <input
              type="number"
              min="1"
              className="wwa-input"
              value={form.level}
              onChange={e => setForm(prev => ({ ...prev, level: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Account Status</label>
            <div style={{ paddingTop: 8 }}>
              <Badge tone={user.accountStatus === 'suspended' ? 'danger' : 'success'}>
                {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
              </Badge>
              <div style={{ fontSize: 11, color: '#b5b8c0', marginTop: 6 }}>
                Managed via Suspend / Reinstate
              </div>
            </div>
          </div>
        </div>
      )}
      {isEditing && (
        <div style={{ fontSize: 11, color: '#b5b8c0', marginTop: -10, marginBottom: 18 }}>
          Level is normally recalculated automatically as the user earns XP.
        </div>
      )}

      <div style={{ marginBottom: 8 }}>
        <div className="wwa-panel-subtitle" style={{ marginBottom: 4 }}>Basic Profile</div>

        <DetailRow label="User ID" value={<span style={monoStyle}>{user.id}</span>} />

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Username</span>
          {isEditing ? (
            <input
              className="wwa-input"
              style={{ maxWidth: 200 }}
              value={form.username}
              onChange={e => setForm(prev => ({ ...prev, username: e.target.value }))}
              placeholder="username"
            />
          ) : (
            <span className="wwa-detail-value">{user.username || '—'}</span>
          )}
        </div>

        <DetailRow label="Email" value={user.email} />

        <DetailRow
          label="Onboarding"
          value={<Badge tone={user.onboardingComplete ? 'success' : 'danger'}>
            {user.onboardingComplete ? 'Complete' : 'Incomplete'}
          </Badge>}
        />
        <DetailRow
          label="Health Connected"
          value={<Badge tone={user.healthConnected ? 'success' : 'neutral'}>
            {user.healthConnected ? 'Connected' : 'Not connected'}
          </Badge>}
        />
        <DetailRow
          label="Wearable Connected"
          value={<Badge tone={user.wearableConnected ? 'success' : 'neutral'}>
            {user.wearableConnected ? 'Connected' : 'Not connected'}
          </Badge>}
        />

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Subscription</span>
          {isEditing ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: form.isPremium ? '#6c63ff' : '#9ca3af' }}>
                {form.isPremium ? 'Premium' : 'Free'}
              </span>
              <ToggleSwitch
                checked={form.isPremium}
                onChange={e => setForm(prev => ({ ...prev, isPremium: e.target.checked }))}
              />
            </div>
          ) : (
            <Badge tone={user.isPremium ? 'brand' : 'neutral'}>
              {user.isPremium ? 'Premium' : 'Free'}
            </Badge>
          )}
        </div>

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Primary Goal</span>
          {isEditing ? (
            <select
              className="wwa-select"
              style={{ maxWidth: 180 }}
              value={form.planMatchGoal}
              onChange={e => setForm(prev => ({ ...prev, planMatchGoal: e.target.value }))}
            >
              {GOAL_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          ) : (
            <span className="wwa-detail-value">{user.planMatchGoal || 'Not set'}</span>
          )}
        </div>

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Hometown</span>
          {isEditing ? (
            <input
              className="wwa-input"
              style={{ maxWidth: 200 }}
              value={form.hometown}
              onChange={e => setForm(prev => ({ ...prev, hometown: e.target.value }))}
              placeholder="Hometown"
            />
          ) : (
            <span className="wwa-detail-value">{user.hometown || '—'}</span>
          )}
        </div>

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Bio</span>
          {isEditing ? (
            <textarea
              className="wwa-input"
              style={{ maxWidth: 260, resize: 'vertical', fontFamily: 'inherit' }}
              rows={2}
              value={form.bio}
              onChange={e => setForm(prev => ({ ...prev, bio: e.target.value }))}
              placeholder="Bio"
            />
          ) : (
            <span className="wwa-detail-value">{user.bio || '—'}</span>
          )}
        </div>

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Preferred Units</span>
          {isEditing ? (
            <select
              className="wwa-select"
              style={{ maxWidth: 180 }}
              value={form.preferredUnits}
              onChange={e => setForm(prev => ({ ...prev, preferredUnits: e.target.value }))}
            >
              {UNITS_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          ) : (
            <span className="wwa-detail-value">{UNITS_LABELS[user.preferredUnits] || '—'}</span>
          )}
        </div>

        <DetailRow label="Total XP" value={user.totalXp !== undefined ? `${user.totalXp} XP` : undefined} />
        <DetailRow label="Weekly XP" value={user.weeklyXp !== undefined ? `${user.weeklyXp} XP` : undefined} />
      </div>

      {!isEditing && (
        <div style={{ marginBottom: 8 }}>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 4 }}>Plan Information</div>
          <DetailRow label="Plan Match Level" value={user.planMatchLevel} />
          <DetailRow label="Plan Match Sport" value={user.planMatchSport} />
          <DetailRow label="Plan Match Days" value={user.planMatchDays} />
          <DetailRow label="Plan Match Equipment" value={equipmentLabel !== '—' ? equipmentLabel : undefined} />
          <DetailRow label="Tracked Plan" value={user.trackedPlanName} />
          <DetailRow
            label="Tracked Plan ID"
            value={user.trackedPlanId ? <span style={monoStyle}>{user.trackedPlanId}</span> : undefined}
          />
          <DetailRow
            label="Saved Plans"
            value={savedPlansCount !== undefined ? `${savedPlansCount} plan${savedPlansCount === 1 ? '' : 's'}` : undefined}
          />
        </div>
      )}

      <div style={{ marginBottom: 8 }}>
        <div className="wwa-panel-subtitle" style={{ marginBottom: 4 }}>Preferences</div>

        {[
          { key: 'notificationsEnabled', label: 'Notifications Enabled' },
          { key: 'workoutReminders', label: 'Workout Reminders' },
          { key: 'streakAlerts', label: 'Streak Alerts' },
          { key: 'wiseCoachMessages', label: 'Wise Coach Messages' },
        ].map(({ key, label }) => {
          const currentValue = user[key] !== false;
          return (
            <div className="wwa-detail-row" key={key}>
              <span className="wwa-detail-label">{label}</span>
              {isEditing ? (
                <ToggleSwitch
                  checked={form[key]}
                  onChange={e => setForm(prev => ({ ...prev, [key]: e.target.checked }))}
                />
              ) : (
                <Badge tone={currentValue ? 'success' : 'neutral'}>
                  {currentValue ? 'Enabled' : 'Disabled'}
                </Badge>
              )}
            </div>
          );
        })}

        <div className="wwa-detail-row">
          <span className="wwa-detail-label">Reminder Time</span>
          {isEditing ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <input
                type="number"
                min="0"
                max="23"
                className="wwa-input wwa-input-sm"
                style={{ width: 60 }}
                value={form.reminderHour}
                onChange={e => setForm(prev => ({ ...prev, reminderHour: e.target.value }))}
              />
              <span>:</span>
              <input
                type="number"
                min="0"
                max="59"
                className="wwa-input wwa-input-sm"
                style={{ width: 60 }}
                value={form.reminderMinute}
                onChange={e => setForm(prev => ({ ...prev, reminderMinute: e.target.value }))}
              />
            </div>
          ) : (
            <span className="wwa-detail-value">
              {formatReminderTime(user.reminderHour, user.reminderMinute) || '—'}
            </span>
          )}
        </div>
      </div>

      {isEditing && (
        <div className="wwa-cell-actions" style={{ marginTop: 8 }}>
          <button className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
          <button className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
            Cancel
          </button>
        </div>
      )}

      {!isEditing && (
        <div style={{ marginTop: 20 }}>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 4 }}>Plan Controls</div>

          {!trackedPlanId ? (
            <div className="wwa-detail-row">
              <span className="wwa-detail-value" style={{ color: '#9ca3af' }}>
                No active plan is being tracked — Break Mode and Compress Control are unavailable.
              </span>
            </div>
          ) : planLoading ? (
            <div className="wwa-detail-row">
              <span className="wwa-detail-value" style={{ color: '#9ca3af' }}>Loading plan status…</span>
            </div>
          ) : (
            <>
              {planActionError && (
                <div className="wwa-alert-error" style={{ marginBottom: 12 }}>{planActionError}</div>
              )}

              <div className="wwa-setting-row" style={{ flexDirection: 'column', alignItems: 'stretch' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
                  <div>
                    <div className="wwa-setting-label">Break Mode</div>
                    <div className="wwa-setting-sub">
                      {planProgress?.breakModeActive
                        ? `Paused until ${planProgress.breakEndDate || '—'}`
                        : 'Plan is actively progressing'}
                    </div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
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
                  <div style={{ marginTop: 12 }}>
                    <DetailRow label="Duration" value={planProgress.breakDays ? `${planProgress.breakDays} days` : '—'} />
                    <DetailRow label="Start Date" value={planProgress.breakStartDate || '—'} />
                    <DetailRow label="Resume Date" value={planProgress.breakEndDate || '—'} />
                    <DetailRow
                      label="Remaining"
                      value={planProgress.breakEndDate ? `${remainingDays(planProgress.breakEndDate)} days` : undefined}
                    />
                  </div>
                ) : (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 12 }}>
                    <span className="wwa-field-label" style={{ marginBottom: 0 }}>Duration</span>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <button
                        className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                        onClick={() => setBreakDaysInput(d => Math.max(MIN_BREAK_DAYS, d - 1))}
                        disabled={savingBreakMode || breakDaysInput <= MIN_BREAK_DAYS}
                      >
                        −
                      </button>
                      <span style={{ fontSize: 14, fontWeight: 700, color: '#111827', minWidth: 56, textAlign: 'center' }}>
                        {breakDaysInput} {breakDaysInput === 1 ? 'day' : 'days'}
                      </span>
                      <button
                        className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                        onClick={() => setBreakDaysInput(d => Math.min(MAX_BREAK_DAYS, d + 1))}
                        disabled={savingBreakMode || breakDaysInput >= MAX_BREAK_DAYS}
                      >
                        +
                      </button>
                    </div>
                  </div>
                )}
              </div>

              <div className="wwa-setting-row">
                <div>
                  <div className="wwa-setting-label">Compress Control</div>
                  <div className="wwa-setting-sub">{`Day ${currentDayIndex} of the tracked plan`}</div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
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
            </>
          )}
        </div>
      )}
    </div>
  );
}

export default UserDetailPanel;
