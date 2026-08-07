import React, { useState, useEffect } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import SkeletonBlock from '../components/ui/SkeletonBlock';

const adminGetSettingsDashboard = httpsCallable(
  functions,
  'adminGetSettingsDashboard'
);

const adminUpdateSettings = httpsCallable(
  functions,
  'adminUpdateSettings'
);

const defaultSubscription = {
  freeTierAIMessages: 10,
  premiumPrice: 9.99,
};

// Fallback shape only — used to fill in genuinely missing fields from
// appConfig/gamification so the form never crashes on a partial document.
// The real values always come from Firestore on load.
const FALLBACK_LEVEL_THRESHOLDS = [0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000];

function mergeConfig(remote) {
  const r = remote || {};
  const indoor = r.cardioAntiCheat?.indoor || {};
  const outdoor = r.cardioAntiCheat?.outdoor || {};
  const speedByActivity = outdoor.maxSpeedKmhByActivity || {};
  const gymCalories = r.gymCalories || {};
  const gymTiming = r.gymTiming || {};
  const xp = r.xp || {};

  return {
    cardioAntiCheat: {
      indoor: {
        accrualPauseDebounceTicks: indoor.accrualPauseDebounceTicks ?? 0,
        accrualResumeDebounceTicks: indoor.accrualResumeDebounceTicks ?? 0,
        stillnessVarianceThreshold: indoor.stillnessVarianceThreshold ?? 0,
        stillnessWindowSeconds: indoor.stillnessWindowSeconds ?? 0,
      },
      outdoor: {
        accrualPauseDebounceTicks: outdoor.accrualPauseDebounceTicks ?? 0,
        accrualResumeDebounceTicks: outdoor.accrualResumeDebounceTicks ?? 0,
        defaultMaxSpeedKmh: outdoor.defaultMaxSpeedKmh ?? 0,
        maxSpeedKmhByActivity: {
          Cycle: speedByActivity.Cycle ?? 0,
          Run: speedByActivity.Run ?? 0,
          Walk: speedByActivity.Walk ?? 0,
        },
        speedRollingWindowSeconds: outdoor.speedRollingWindowSeconds ?? 0,
        stationaryThresholdMeters: outdoor.stationaryThresholdMeters ?? 0,
        stationaryWindowSeconds: outdoor.stationaryWindowSeconds ?? 0,
      },
    },
    gymCalories: {
      minCalories: gymCalories.minCalories ?? 0,
      maxCalories: gymCalories.maxCalories ?? 0,
      setsCoefficient: gymCalories.setsCoefficient ?? 0,
      volumeCoefficient: gymCalories.volumeCoefficient ?? 0,
    },
    gymTiming: {
      minSecondsPerRep: gymTiming.minSecondsPerRep ?? 0,
      minSetTransitionSeconds: gymTiming.minSetTransitionSeconds ?? 0,
    },
    levelThresholds: Array.isArray(r.levelThresholds) && r.levelThresholds.length > 0
      ? r.levelThresholds.map(v => Number(v) || 0)
      : [...FALLBACK_LEVEL_THRESHOLDS],
    xp: {
      cardioMinXp: xp.cardioMinXp ?? 0,
      cardioMaxXp: xp.cardioMaxXp ?? 0,
      cardioPerCalorieRate: xp.cardioPerCalorieRate ?? 0,
      gymPerSet: xp.gymPerSet ?? 0,
    },
  };
}

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const isNonNegInt = (v) => isNum(v) && Number.isInteger(v) && v >= 0;
const isNonNegNum = (v) => isNum(v) && v >= 0;
const isPositiveNum = (v) => isNum(v) && v > 0;

// Returns a flat map of "path.to.field" -> error message for every invalid
// leaf in the config tree, so each input can show its own inline message.
function validateConfig(config) {
  const errors = {};
  const checkInt = (path, value) => {
    if (!isNonNegInt(value)) errors[path] = 'Must be a non-negative whole number.';
  };
  const checkNonNeg = (path, value) => {
    if (!isNonNegNum(value)) errors[path] = 'Must be a non-negative number.';
  };
  const checkPositive = (path, value) => {
    if (!isPositiveNum(value)) errors[path] = 'Must be a positive number.';
  };

  const { indoor, outdoor } = config.cardioAntiCheat;
  checkInt('indoor.accrualPauseDebounceTicks', indoor.accrualPauseDebounceTicks);
  checkInt('indoor.accrualResumeDebounceTicks', indoor.accrualResumeDebounceTicks);
  checkNonNeg('indoor.stillnessVarianceThreshold', indoor.stillnessVarianceThreshold);
  checkNonNeg('indoor.stillnessWindowSeconds', indoor.stillnessWindowSeconds);

  checkInt('outdoor.accrualPauseDebounceTicks', outdoor.accrualPauseDebounceTicks);
  checkInt('outdoor.accrualResumeDebounceTicks', outdoor.accrualResumeDebounceTicks);
  checkPositive('outdoor.defaultMaxSpeedKmh', outdoor.defaultMaxSpeedKmh);
  checkPositive('outdoor.maxSpeedKmhByActivity.Cycle', outdoor.maxSpeedKmhByActivity.Cycle);
  checkPositive('outdoor.maxSpeedKmhByActivity.Run', outdoor.maxSpeedKmhByActivity.Run);
  checkPositive('outdoor.maxSpeedKmhByActivity.Walk', outdoor.maxSpeedKmhByActivity.Walk);
  checkNonNeg('outdoor.speedRollingWindowSeconds', outdoor.speedRollingWindowSeconds);
  checkNonNeg('outdoor.stationaryThresholdMeters', outdoor.stationaryThresholdMeters);
  checkNonNeg('outdoor.stationaryWindowSeconds', outdoor.stationaryWindowSeconds);

  const { gymCalories, gymTiming, xp, levelThresholds } = config;
  checkNonNeg('gymCalories.minCalories', gymCalories.minCalories);
  checkNonNeg('gymCalories.maxCalories', gymCalories.maxCalories);
  checkNonNeg('gymCalories.setsCoefficient', gymCalories.setsCoefficient);
  checkNonNeg('gymCalories.volumeCoefficient', gymCalories.volumeCoefficient);
  if (!errors['gymCalories.minCalories'] && !errors['gymCalories.maxCalories']
    && gymCalories.maxCalories < gymCalories.minCalories) {
    errors['gymCalories.maxCalories'] = 'Must be greater than or equal to minimum calories.';
  }

  checkNonNeg('gymTiming.minSecondsPerRep', gymTiming.minSecondsPerRep);
  checkNonNeg('gymTiming.minSetTransitionSeconds', gymTiming.minSetTransitionSeconds);

  checkNonNeg('xp.cardioMinXp', xp.cardioMinXp);
  checkNonNeg('xp.cardioMaxXp', xp.cardioMaxXp);
  if (!errors['xp.cardioMinXp'] && !errors['xp.cardioMaxXp'] && xp.cardioMaxXp < xp.cardioMinXp) {
    errors['xp.cardioMaxXp'] = 'Must be greater than or equal to cardio minimum XP.';
  }
  checkInt('xp.gymPerSet', xp.gymPerSet);
  checkNonNeg('xp.cardioPerCalorieRate', xp.cardioPerCalorieRate);

  levelThresholds.forEach((val, i) => {
    const path = `levelThresholds.${i}`;
    if (!isNonNegInt(val)) {
      errors[path] = 'Must be a non-negative whole number.';
      return;
    }
    if (i === 0 && val !== 0) {
      errors[path] = 'Level 1 must remain 0.';
      return;
    }
    if (i > 0 && val <= levelThresholds[i - 1]) {
      errors[path] = `Must be greater than Level ${i}'s threshold.`;
    }
  });

  return errors;
}

const LEAF_PATHS = [
  ['cardioAntiCheat', 'indoor', 'accrualPauseDebounceTicks'],
  ['cardioAntiCheat', 'indoor', 'accrualResumeDebounceTicks'],
  ['cardioAntiCheat', 'indoor', 'stillnessVarianceThreshold'],
  ['cardioAntiCheat', 'indoor', 'stillnessWindowSeconds'],
  ['cardioAntiCheat', 'outdoor', 'accrualPauseDebounceTicks'],
  ['cardioAntiCheat', 'outdoor', 'accrualResumeDebounceTicks'],
  ['cardioAntiCheat', 'outdoor', 'defaultMaxSpeedKmh'],
  ['cardioAntiCheat', 'outdoor', 'maxSpeedKmhByActivity', 'Cycle'],
  ['cardioAntiCheat', 'outdoor', 'maxSpeedKmhByActivity', 'Run'],
  ['cardioAntiCheat', 'outdoor', 'maxSpeedKmhByActivity', 'Walk'],
  ['cardioAntiCheat', 'outdoor', 'speedRollingWindowSeconds'],
  ['cardioAntiCheat', 'outdoor', 'stationaryThresholdMeters'],
  ['cardioAntiCheat', 'outdoor', 'stationaryWindowSeconds'],
  ['gymCalories', 'minCalories'],
  ['gymCalories', 'maxCalories'],
  ['gymCalories', 'setsCoefficient'],
  ['gymCalories', 'volumeCoefficient'],
  ['gymTiming', 'minSecondsPerRep'],
  ['gymTiming', 'minSetTransitionSeconds'],
  ['xp', 'cardioMinXp'],
  ['xp', 'cardioMaxXp'],
  ['xp', 'cardioPerCalorieRate'],
  ['xp', 'gymPerSet'],
];
const getIn = (obj, path) => path.reduce((acc, k) => (acc == null ? undefined : acc[k]), obj);

// Builds a Firestore dot-path partial update containing only leaves that
// actually changed, so sibling fields (including ones this form doesn't
// show) are never touched. levelThresholds is a top-level array field —
// Firestore has no dot-path addressing for array indices — so it's written
// whole only when it changed, which never affects any other appConfig field.
function buildUpdates(current, original) {
  const updates = {};
  LEAF_PATHS.forEach(path => {
    const newVal = getIn(current, path);
    const oldVal = getIn(original, path);
    if (newVal !== oldVal) updates[path.join('.')] = newVal;
  });
  if (JSON.stringify(current.levelThresholds) !== JSON.stringify(original.levelThresholds)) {
    updates.levelThresholds = current.levelThresholds;
  }
  return updates;
}

function setNested(obj, path, value) {
  if (path.length === 1) return { ...obj, [path[0]]: value };
  const [head, ...rest] = path;
  return { ...obj, [head]: setNested(obj[head] || {}, rest, value) };
}

function NumberField({ label, value, error, onChange, step = 1 }) {
  return (
    <div>
      <label className="wwa-field-label">{label}</label>
      <input
        type="number"
        step={step}
        className="wwa-input"
        value={value}
        onChange={e => onChange(e.target.value === '' ? 0 : Number(e.target.value))}
      />
      {error && <div style={{ color: '#cc3333', fontSize: 12, marginTop: 4 }}>{error}</div>}
    </div>
  );
}

function SettingRow({ label, sub, children }) {
  return (
    <div className="wwa-setting-row">
      <div>
        <div className="wwa-setting-label">{label}</div>
        {sub && <div className="wwa-setting-sub">{sub}</div>}
      </div>
      {children}
    </div>
  );
}

function Settings() {
  const [subscription, setSubscription] = useState(defaultSubscription);
  const [loadedSubscription, setLoadedSubscription] = useState(defaultSubscription);

  const [config, setConfig] = useState(null);
  const [loadedConfig, setLoadedConfig] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

  const [fieldErrors, setFieldErrors] = useState({});
  const [confirmingSave, setConfirmingSave] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState('');
  const [saveSuccess, setSaveSuccess] = useState('');

  useEffect(() => {
    const fetchConfig = async () => {
      try {
        const result = await adminGetSettingsDashboard();

        const gamification = result.data.gamification;
        const subscription = result.data.subscription;

        const merged = mergeConfig(gamification);

        setConfig(merged);
        setLoadedConfig(merged);
        const loadedSubscriptionData = {
          freeTierAIMessages:
            Number.isInteger(subscription?.freeTierAIMessages)
              ? subscription.freeTierAIMessages
              : defaultSubscription.freeTierAIMessages,
          premiumPrice:
            Number.isFinite(Number(subscription?.premiumPrice))
              ? Number(subscription.premiumPrice)
              : defaultSubscription.premiumPrice,
        };
        
        setSubscription(loadedSubscriptionData);
        setLoadedSubscription(loadedSubscriptionData);
      } catch (err) {
        console.error(err);
        const detail = err && err.code ? ` (${err.code})` : '';
        setLoadError(`Failed to load system configuration.${detail}`);
      }
      setLoading(false);
    };
    fetchConfig();
  }, []);

  const set = (path) => (value) => setConfig(prev => setNested(prev, path, value));

  const setLevelThreshold = (index, value) => {
    setConfig(prev => {
      const next = [...prev.levelThresholds];
      next[index] = value;
      return { ...prev, levelThresholds: next };
    });
  };

  const handleSaveClick = () => {
    const errors = validateConfig(config);
    if (
      !Number.isInteger(subscription.freeTierAIMessages) ||
      subscription.freeTierAIMessages < 0
    ) {
      errors['subscription.freeTierAIMessages'] =
        'Free-tier AI messages must be a non-negative whole number.';
    }
    
    if (
      !Number.isFinite(subscription.premiumPrice) ||
      subscription.premiumPrice < 0
    ) {
      errors['subscription.premiumPrice'] =
        'Premium price must be a non-negative number.';
    }
    setFieldErrors(errors);
    setSaveError('');
    setSaveSuccess('');
    if (Object.keys(errors).length > 0) {
      setSaveError('Please fix the highlighted fields before saving.');
      return;
    }
    setConfirmingSave(true);
  };

  const handleCancelSave = () => setConfirmingSave(false);

  const handleConfirmSave = async () => {
    const updates = buildUpdates(config, loadedConfig);
  
    setConfirmingSave(false);
    setSaving(true);
    setSaveError('');
    setSaveSuccess('');
  
    try {
      await adminUpdateSettings({
        subscription,
        gamificationUpdates: updates,
      });
  
      setLoadedConfig(config);
      setLoadedSubscription(subscription);
  
      setSaveSuccess('Settings saved successfully.');
      setTimeout(() => setSaveSuccess(''), 3000);
    } catch (err) {
      console.error('Failed to save settings:', err);
  
      const detail = err?.code ? ` (${err.code})` : '';
  
      setSaveError(
        `Failed to save settings.${detail} Please try again.`
      );
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    if (loadedConfig) {
      setConfig(loadedConfig);
    }
  
    setSubscription(loadedSubscription);
    setFieldErrors({});
    setSaveError('');
    setSaveSuccess('');
    setConfirmingSave(false);
  };

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Settings"
        subtitle="Configure platform rules and gamification"
        actions={(
          <>
            {saveSuccess && (
              <span className="wwa-status-pill">
                <span className="wwa-status-dot" />
                {saveSuccess}
              </span>
            )}
            <button
              className="wwa-btn wwa-btn-secondary"
              onClick={handleReset}
              disabled={saving || !loadedConfig}
            >
              Reset
            </button>
            <button
              className="wwa-btn wwa-btn-primary"
              onClick={handleSaveClick}
              disabled={saving || loading || !config}
            >
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
          </>
        )}
      />

      {saveError && (
        <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{saveError}</div>
      )}

      {confirmingSave && (
        <div style={{
          background: '#f9fafb',
          border: '1px solid #eef0f4',
          borderRadius: 12,
          padding: '14px 16px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 12,
          marginBottom: 20,
        }}>
          <span style={{ fontSize: 14, fontWeight: 600, color: '#111827' }}>
            Save these system configuration changes?
          </span>
          <div className="wwa-cell-actions">
            <button className="wwa-btn wwa-btn-secondary" onClick={handleCancelSave} disabled={saving}>
              Cancel
            </button>
            <button className="wwa-btn wwa-btn-primary" onClick={handleConfirmSave} disabled={saving}>
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
          </div>
        </div>
      )}

      {loading ? (
        <SkeletonBlock height={220} style={{ marginBottom: 24 }} />
      ) : loadError ? (
        <div className="wwa-panel">
          <div className="wwa-alert-error">{loadError}</div>
        </div>
      ) : config && (
        <>
          <div className="wwa-panel">
            <div className="wwa-panel-title">XP Settings</div>
            <div className="wwa-panel-subtitle">Controls how much XP cardio and gym sessions award.</div>
            <div className="wwa-form-grid">
              <NumberField
                label="Cardio Minimum XP"
                value={config.xp.cardioMinXp}
                error={fieldErrors['xp.cardioMinXp']}
                onChange={set(['xp', 'cardioMinXp'])}
              />
              <NumberField
                label="Cardio Maximum XP"
                value={config.xp.cardioMaxXp}
                error={fieldErrors['xp.cardioMaxXp']}
                onChange={set(['xp', 'cardioMaxXp'])}
              />
              <NumberField
                label="Cardio XP Per Calorie"
                value={config.xp.cardioPerCalorieRate}
                error={fieldErrors['xp.cardioPerCalorieRate']}
                onChange={set(['xp', 'cardioPerCalorieRate'])}
                step="any"
              />
              <NumberField
                label="Gym XP Per Set"
                value={config.xp.gymPerSet}
                error={fieldErrors['xp.gymPerSet']}
                onChange={set(['xp', 'gymPerSet'])}
              />
            </div>
          </div>

          <div className="wwa-panel">
            <div className="wwa-panel-title">Level Thresholds</div>
            <div className="wwa-panel-subtitle">
              Total XP required to reach each level. Index 0 is Level 1 and must stay 0; each level must require more XP than the last.
            </div>
            <div className="wwa-table-wrap">
              <table className="wwa-table">
                <thead>
                  <tr>
                    <th>Level</th>
                    <th>XP Required</th>
                  </tr>
                </thead>
                <tbody>
                  {config.levelThresholds.map((xpRequired, i) => (
                    <tr key={i}>
                      <td className="wwa-cell-primary">Level {i + 1}</td>
                      <td>
                        <input
                          type="number"
                          step={1}
                          className="wwa-input wwa-input-sm"
                          style={{ width: 120, textAlign: 'left' }}
                          value={xpRequired}
                          onChange={e => setLevelThreshold(i, e.target.value === '' ? 0 : Number(e.target.value))}
                        />
                        {fieldErrors[`levelThresholds.${i}`] && (
                          <div style={{ color: '#cc3333', fontSize: 12, marginTop: 4 }}>
                            {fieldErrors[`levelThresholds.${i}`]}
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="wwa-panel">
            <div className="wwa-panel-title">Gym Calories</div>
            <div className="wwa-panel-subtitle">
              Controls gym calorie estimation and abuse limits — bounds how many calories a single session can report.
            </div>
            <div className="wwa-form-grid">
              <NumberField
                label="Minimum Calories"
                value={config.gymCalories.minCalories}
                error={fieldErrors['gymCalories.minCalories']}
                onChange={set(['gymCalories', 'minCalories'])}
              />
              <NumberField
                label="Maximum Calories"
                value={config.gymCalories.maxCalories}
                error={fieldErrors['gymCalories.maxCalories']}
                onChange={set(['gymCalories', 'maxCalories'])}
              />
              <NumberField
                label="Sets Coefficient"
                value={config.gymCalories.setsCoefficient}
                error={fieldErrors['gymCalories.setsCoefficient']}
                onChange={set(['gymCalories', 'setsCoefficient'])}
                step="any"
              />
              <NumberField
                label="Volume Coefficient"
                value={config.gymCalories.volumeCoefficient}
                error={fieldErrors['gymCalories.volumeCoefficient']}
                onChange={set(['gymCalories', 'volumeCoefficient'])}
                step="any"
              />
            </div>
          </div>

          <div className="wwa-panel">
            <div className="wwa-panel-title">Gym Timing</div>
            <div className="wwa-panel-subtitle">Minimum pacing enforced between reps and between sets.</div>
            <div className="wwa-form-grid">
              <NumberField
                label="Minimum Seconds Per Rep"
                value={config.gymTiming.minSecondsPerRep}
                error={fieldErrors['gymTiming.minSecondsPerRep']}
                onChange={set(['gymTiming', 'minSecondsPerRep'])}
                step="any"
              />
              <NumberField
                label="Minimum Set Transition Seconds"
                value={config.gymTiming.minSetTransitionSeconds}
                error={fieldErrors['gymTiming.minSetTransitionSeconds']}
                onChange={set(['gymTiming', 'minSetTransitionSeconds'])}
                step="any"
              />
            </div>
          </div>

          <div className="wwa-panel">
            <div className="wwa-panel-title">Cardio Anti-Cheat</div>
            <div className="wwa-panel-subtitle">Thresholds used to detect stationary/idle cheating during cardio sessions.</div>

            <div className="wwa-panel-subtitle" style={{ fontWeight: 700, color: '#374151', marginTop: 8 }}>Indoor</div>
            <div className="wwa-form-grid">
              <NumberField
                label="Accrual Pause Debounce Ticks"
                value={config.cardioAntiCheat.indoor.accrualPauseDebounceTicks}
                error={fieldErrors['indoor.accrualPauseDebounceTicks']}
                onChange={set(['cardioAntiCheat', 'indoor', 'accrualPauseDebounceTicks'])}
              />
              <NumberField
                label="Accrual Resume Debounce Ticks"
                value={config.cardioAntiCheat.indoor.accrualResumeDebounceTicks}
                error={fieldErrors['indoor.accrualResumeDebounceTicks']}
                onChange={set(['cardioAntiCheat', 'indoor', 'accrualResumeDebounceTicks'])}
              />
              <NumberField
                label="Stillness Variance Threshold"
                value={config.cardioAntiCheat.indoor.stillnessVarianceThreshold}
                error={fieldErrors['indoor.stillnessVarianceThreshold']}
                onChange={set(['cardioAntiCheat', 'indoor', 'stillnessVarianceThreshold'])}
                step="any"
              />
              <NumberField
                label="Stillness Window Seconds"
                value={config.cardioAntiCheat.indoor.stillnessWindowSeconds}
                error={fieldErrors['indoor.stillnessWindowSeconds']}
                onChange={set(['cardioAntiCheat', 'indoor', 'stillnessWindowSeconds'])}
                step="any"
              />
            </div>

            <div className="wwa-panel-subtitle" style={{ fontWeight: 700, color: '#374151', marginTop: 20 }}>Outdoor</div>
            <div className="wwa-form-grid">
              <NumberField
                label="Accrual Pause Debounce Ticks"
                value={config.cardioAntiCheat.outdoor.accrualPauseDebounceTicks}
                error={fieldErrors['outdoor.accrualPauseDebounceTicks']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'accrualPauseDebounceTicks'])}
              />
              <NumberField
                label="Accrual Resume Debounce Ticks"
                value={config.cardioAntiCheat.outdoor.accrualResumeDebounceTicks}
                error={fieldErrors['outdoor.accrualResumeDebounceTicks']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'accrualResumeDebounceTicks'])}
              />
              <NumberField
                label="Default Max Speed (km/h)"
                value={config.cardioAntiCheat.outdoor.defaultMaxSpeedKmh}
                error={fieldErrors['outdoor.defaultMaxSpeedKmh']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'defaultMaxSpeedKmh'])}
                step="any"
              />
              <NumberField
                label="Cycle Max Speed (km/h)"
                value={config.cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Cycle}
                error={fieldErrors['outdoor.maxSpeedKmhByActivity.Cycle']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'maxSpeedKmhByActivity', 'Cycle'])}
                step="any"
              />
              <NumberField
                label="Run Max Speed (km/h)"
                value={config.cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Run}
                error={fieldErrors['outdoor.maxSpeedKmhByActivity.Run']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'maxSpeedKmhByActivity', 'Run'])}
                step="any"
              />
              <NumberField
                label="Walk Max Speed (km/h)"
                value={config.cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Walk}
                error={fieldErrors['outdoor.maxSpeedKmhByActivity.Walk']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'maxSpeedKmhByActivity', 'Walk'])}
                step="any"
              />
              <NumberField
                label="Speed Rolling Window Seconds"
                value={config.cardioAntiCheat.outdoor.speedRollingWindowSeconds}
                error={fieldErrors['outdoor.speedRollingWindowSeconds']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'speedRollingWindowSeconds'])}
                step="any"
              />
              <NumberField
                label="Stationary Threshold Metres"
                value={config.cardioAntiCheat.outdoor.stationaryThresholdMeters}
                error={fieldErrors['outdoor.stationaryThresholdMeters']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'stationaryThresholdMeters'])}
                step="any"
              />
              <NumberField
                label="Stationary Window Seconds"
                value={config.cardioAntiCheat.outdoor.stationaryWindowSeconds}
                error={fieldErrors['outdoor.stationaryWindowSeconds']}
                onChange={set(['cardioAntiCheat', 'outdoor', 'stationaryWindowSeconds'])}
                step="any"
              />
            </div>
          </div>
        </>
      )}

<div className="wwa-panel">
  <div className="wwa-panel-title">Subscription</div>
  <div className="wwa-panel-subtitle">Free vs premium tier limits</div>

  <SettingRow
    label="Free tier AI messages/month"
    sub="Cap for free users on WiseCoach chat"
  >
    <div>
      <input
        type="number"
        min="0"
        step="1"
        className="wwa-input wwa-input-sm"
        value={subscription.freeTierAIMessages}
        onChange={e =>
          setSubscription(prev => ({
            ...prev,
            freeTierAIMessages:
              e.target.value === ''
                ? 0
                : Number(e.target.value),
          }))
        }
      />

      {fieldErrors['subscription.freeTierAIMessages'] && (
        <div
          style={{
            color: '#cc3333',
            fontSize: 12,
            marginTop: 4,
          }}
        >
          {fieldErrors['subscription.freeTierAIMessages']}
        </div>
      )}
    </div>
  </SettingRow>

  <SettingRow
    label="Premium price (USD/month)"
    sub="Monthly subscription price"
  >
    <div>
      <input
        type="number"
        min="0"
        step="0.01"
        className="wwa-input wwa-input-sm"
        value={subscription.premiumPrice}
        onChange={e =>
          setSubscription(prev => ({
            ...prev,
            premiumPrice:
              e.target.value === ''
                ? 0
                : Number(e.target.value),
          }))
        }
      />

      {fieldErrors['subscription.premiumPrice'] && (
        <div
          style={{
            color: '#cc3333',
            fontSize: 12,
            marginTop: 4,
          }}
        >
          {fieldErrors['subscription.premiumPrice']}
        </div>
      )}
    </div>
  </SettingRow>
</div>
    </div>
  );
}

export default Settings;
