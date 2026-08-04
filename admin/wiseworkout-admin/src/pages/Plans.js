import React, { useState, useEffect } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import PlanDetailPanel from '../components/PlanDetailPanel';
import PlanSessionsEditor, {
  buildDefaultSessions, buildAndValidateSessions,
} from '../components/PlanSessionsEditor';
import ImageThumb from '../components/ui/ImageThumb';
import { formatEquipment } from '../utils/formatUtils';
import { parseCommaList, buildDesignedBy } from '../utils/planUtils';

// Canonical values already established elsewhere in the codebase (Badge tones
// in Plans.js/plan_detail_screen.dart's level styling, the app's Gym/Running
// catalog sports) — offered first, then unioned with whatever real distinct
// values the loaded data already contains. 'Custom' is excluded here since
// it's reserved for user-created plans and is never a valid choice when
// adding a new *official* plan.
const CANONICAL_LEVELS = ['Beginner', 'Intermediate', 'Advanced'];
const CANONICAL_TYPES = ['Gym', 'Running'];

const emptyAddForm = {
  name: '', level: 'Beginner', type: 'Gym', durationWeeks: '', daysPerWeek: '', equipment: '', description: '',
  goals: '', matchGoals: '', matchSport: 'Gym', matchLevel: 'Beginner', isActive: true, imageUrl: '',
  designedByName: '', designedByTitle: '', designedByCredential: '', designedByQuote: '',
};

function Plans() {
  const [plans, setPlans] = useState([]);
  const [usersById, setUsersById] = useState({});
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [levelFilter, setLevelFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all');
  const [sourceFilter, setSourceFilter] = useState('all');
  const [daysFilter, setDaysFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedPlanId, setSelectedPlanId] = useState(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [addForm, setAddForm] = useState(emptyAddForm);
  const [addSessions, setAddSessions] = useState(() => buildDefaultSessions(emptyAddForm.daysPerWeek));
  const [addSaving, setAddSaving] = useState(false);
  const [addError, setAddError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [exerciseCatalog, setExerciseCatalog] = useState([]);

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
  
      try {
        const adminListPlansDashboard = httpsCallable(
          functions,
          'adminListPlansDashboard'
        );
  
        const result = await adminListPlansDashboard();
        const data = result.data || {};
  
        const loadedPlans = Array.isArray(data.plans)
          ? data.plans
          : [];
  
        setPlans(loadedPlans);
  
        const byId = {};
        const loadedUsers = Array.isArray(data.users)
          ? data.users
          : [];
  
        loadedUsers.forEach(user => {
          byId[user.id] = user;
        });
  
        setUsersById(byId);
  
        const catalog = Array.isArray(data.exercises)
          ? data.exercises
              .filter(exercise => exercise.name)
              .map(exercise => ({
                name: exercise.name,
                muscle: exercise.muscleGroup || '',
              }))
          : [];
  
        setExerciseCatalog(catalog);
      } catch (err) {
        console.error('Failed to load plans dashboard:', err);
  
        window.alert(
          `Failed to load plans dashboard.${
            err?.code ? ` (${err.code})` : ''
          }`
        );
      } finally {
        setLoading(false);
      }
    };
  
    fetchData();
  }, []);

  // For custom plans, resolves createdBy against the already-loaded users
  // map (name, then email, then the raw UID as a last resort). Official/
  // system plans aren't attributed to any admin-managed creator flow, so
  // they're labelled with the app's own catalog attribution ("WiseWorkout",
  // matching plan_detail_screen.dart's "WiseWorkout Certified" plans).
  const getCreatorLabel = (plan) => {
    if (!plan.isCustom) return (plan.designedBy && plan.designedBy.name) || 'WiseWorkout';
    const uid = plan.createdBy;
    if (!uid) return '—';
    const user = usersById[uid];
    return (user && (user.displayName || user.email)) || uid;
  };

  // Distinct values actually present in the loaded data — no hardcoded lists.
  const levels = Array.from(new Set(plans.map(p => p.level).filter(Boolean))).sort();
  const types = Array.from(new Set(plans.map(p => p.type).filter(Boolean))).sort();
  const daysOptions = Array.from(new Set(plans.map(p => p.daysPerWeek).filter(d => d !== undefined && d !== null)))
    .sort((a, b) => a - b);

  const levelOptions = Array.from(new Set([...CANONICAL_LEVELS, ...levels]))
    .filter(l => l.toLowerCase() !== 'custom');
  const typeOptions = Array.from(new Set([...CANONICAL_TYPES, ...types]));

  // Creates a new official/system plan matching the real official-plan
  // schema found in Firestore: no `isCustom` field at all (official plans
  // simply omit it — they aren't marked isCustom: false), no `createdBy`,
  // no `createdAt`/serverTimestamp (existing official plans have neither).
  // `sessions` must be fully populated — every consumer in the mobile app
  // (plan_detail_screen.dart, plan_schedule_screen.dart, gym_session_screen.dart,
  // home_screen.dart) expects real session/exercise data, and an empty
  // sessions: [] plan renders as blank/broken there.
  const handleAddPlan = async () => {
    if (!addForm.name.trim()) { setAddError('Plan Name is required.'); return; }
    if (!addForm.level) { setAddError('Level is required.'); return; }
    if (!addForm.type) { setAddError('Type is required.'); return; }
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
    // Cross-checks daysPerWeek against the actual number of non-rest
    // sessions built and blocks saving on mismatch — see buildAndValidateSessions.
    const { sessions, error: sessionsError } = buildAndValidateSessions(addSessions, days);
    if (sessionsError) { setAddError(sessionsError); return; }

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
        matchGoals: matchGoalsList,
        matchLevel: addForm.matchLevel || addForm.level,
        matchSport: addForm.matchSport || addForm.type,
        imageUrl: addForm.imageUrl.trim(),
      };
      if (designedBy) payload.designedBy = designedBy;

      const adminCreateOfficialPlan = httpsCallable(
        functions,
        'adminCreateOfficialPlan'
      );
      
      const result = await adminCreateOfficialPlan({
        plan: payload,
      });
      
      setPlans(prev => [
        ...prev,
        {
          id: result.data.planId,
          ...(result.data.plan || payload),
        },
      ]);
      setShowAddForm(false);
      setAddForm(emptyAddForm);
      setAddSessions(buildDefaultSessions(emptyAddForm.daysPerWeek));
      setSuccessMsg('Plan created successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setAddError('Failed to create plan. Please try again.');
    }
    setAddSaving(false);
  };

  // Used for both custom-plan edits (PlanDetailPanel enforces which fields are
  // editable there) and official-plan edits — writes only the changed fields
  // plus updatedAt. Official plans don't have isCustom/createdBy/createdAt
  // (see handleAddPlan above), but stamping updatedAt on edit is harmless
  // additive bookkeeping nothing in the app depends on being absent.
  const handleSavePlan = async (planId, changes) => {
    const adminUpdatePlan = httpsCallable(
      functions,
      'adminUpdatePlan'
    );
  
    const result = await adminUpdatePlan({
      planId,
      changes,
    });
  
    const savedPlan = result.data.plan || changes;
  
    setPlans(prev =>
      prev.map(plan =>
        plan.id === planId
          ? {
              ...plan,
              ...savedPlan,
              updatedAt: new Date().toISOString(),
            }
          : plan
      )
    );
  };

  // Mirrors FirestoreService.deleteCustomPlan exactly for custom plans:
  // deletes the plan doc, the creator's matching customRoutines doc(s), and
  // the creator's own planProgress entry (guarded by plan.createdBy, which
  // official plans never have — so this already no-ops safely for them).
  // Does not touch trackedPlanId/trackedPlanName/savedPlanIds on OTHER users
  // anywhere — the app itself never cleans those up either. A stale reference
  // left on some other user's document is not a crash: getTrackedPlan() checks
  // planDoc.exists() and returns null, and the Saved-plans list cross-references
  // live getPlans() results, so a deleted plan just silently drops out of view.
  // Doing a full users-collection scan/rewrite to purge those references would
  // be a much larger, riskier operation than this delete button implies.
  const handleDeletePlan = async (plan) => {
    const planName = plan.name || plan.title || plan.id;
  
    const confirmation = window.prompt(
      `Permanently delete "${planName}"?\n\n` +
      `${
        plan.isCustom
          ? 'This also removes the creator’s matching custom routine and plan progress.'
          : 'This removes the official plan from the shared plan library.'
      }\n\n` +
      'Type DELETE to continue:'
    );
  
    if (confirmation !== 'DELETE') return;
  
    const adminDeletePlan = httpsCallable(
      functions,
      'adminDeletePlan'
    );
  
    await adminDeletePlan({
      planId: plan.id,
    });
  
    setPlans(prev =>
      prev.filter(existing => existing.id !== plan.id)
    );
  
    setSelectedPlanId(null);
  
    setSuccessMsg(
      `${plan.isCustom ? 'Custom' : 'Official'} plan deleted successfully`
    );
  
    setTimeout(() => setSuccessMsg(''), 3000);
  };

  const hasActiveFilters = Boolean(
    search || levelFilter !== 'all' || typeFilter !== 'all' ||
    sourceFilter !== 'all' || daysFilter !== 'all' || statusFilter !== 'all'
  );

  const resetFilters = () => {
    setSearch('');
    setLevelFilter('all');
    setTypeFilter('all');
    setSourceFilter('all');
    setDaysFilter('all');
    setStatusFilter('all');
  };

  const filtered = plans.filter(p => {
    const q = search.toLowerCase();
    const matchesSearch = !q ||
      (p.title || p.name || '').toLowerCase().includes(q) ||
      (p.level || '').toLowerCase().includes(q);
    const matchesLevel = levelFilter === 'all' || p.level === levelFilter;
    const matchesType = typeFilter === 'all' || p.type === typeFilter;
    const matchesSource = sourceFilter === 'all' ||
      (sourceFilter === 'custom' ? !!p.isCustom : !p.isCustom);
    const matchesDays = daysFilter === 'all' || p.daysPerWeek === Number(daysFilter);
    const matchesStatus = statusFilter === 'all' ||
      (statusFilter === 'active' ? p.isActive !== false : p.isActive === false);
    return matchesSearch && matchesLevel && matchesType && matchesSource && matchesDays && matchesStatus;
  });

  const selectedPlan = plans.find(p => p.id === selectedPlanId) || null;

  const levelTone = (level) =>
    level === 'Advanced' ? 'danger' : level === 'Intermediate' ? 'warning' : 'success';

  // Exports exactly the rows currently matching search + filters. Missing
  // values use "-" per spec (distinct from the "—" used elsewhere on-screen).
  const handleExport = () => {
    const rows = filtered.map(p => {
      const creator = getCreatorLabel(p);
      return {
        'Plan Name': p.title || p.name || '-',
        Level: p.level || '-',
        Duration: p.durationWeeks ? `${p.durationWeeks}w` : '-',
        'Days/Week': p.daysPerWeek ? `${p.daysPerWeek} days` : '-',
        Equipment: Array.isArray(p.equipment)
          ? (p.equipment.length > 0 ? p.equipment.join(', ') : '-')
          : (p.equipment || '-'),
        Type: p.type || p.category || '-',
        Source: p.isCustom ? 'Custom' : 'Official',
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

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Plans"
        subtitle={loading ? 'Loading plans…' : `${plans.length} plans in the library`}
        actions={!loading && (
          <>
            {successMsg && (
              <span className="wwa-status-pill">
                <span className="wwa-status-dot" />
                {successMsg}
              </span>
            )}
            <button
              className="wwa-btn wwa-btn-primary"
              onClick={() => {
                setShowAddForm(!showAddForm);
                setAddError('');
                setAddForm(emptyAddForm);
                setAddSessions(buildDefaultSessions(emptyAddForm.daysPerWeek));
              }}
            >
              + Add Plan
            </button>
            <button
              className="wwa-btn wwa-btn-sm wwa-btn-success"
              onClick={handleExport}
              disabled={filtered.length === 0}
            >
              📤 Export to Excel
            </button>
          </>
        )}
      />

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <>
          {showAddForm && (
            <div className="wwa-panel">
              <div className="wwa-panel-title">New Official Plan</div>
              <div className="wwa-panel-subtitle">Creates a system plan — not attributed to any user</div>

              {addError && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{addError}</div>}

              <div className="wwa-form-grid">
                <div>
                  <label className="wwa-field-label">Plan Name</label>
                  <input
                    className="wwa-input"
                    value={addForm.name}
                    onChange={e => setAddForm(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="e.g. Fat Loss Circuit"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Level</label>
                  <select
                    className="wwa-select"
                    value={addForm.level}
                    onChange={e => setAddForm(prev => ({ ...prev, level: e.target.value, matchLevel: e.target.value }))}
                  >
                    {levelOptions.map(l => <option key={l} value={l}>{l}</option>)}
                  </select>
                </div>
                <div>
                  <label className="wwa-field-label">Type</label>
                  <select
                    className="wwa-select"
                    value={addForm.type}
                    onChange={e => setAddForm(prev => ({ ...prev, type: e.target.value, matchSport: e.target.value }))}
                  >
                    {typeOptions.map(t => <option key={t} value={t}>{t}</option>)}
                  </select>
                </div>
                <div>
                  <label className="wwa-field-label">Days per Week</label>
                  <input
                    type="number"
                    min="1"
                    className="wwa-input"
                    value={addForm.daysPerWeek}
                    onChange={e => setAddForm(prev => ({ ...prev, daysPerWeek: e.target.value }))}
                    placeholder="e.g. 3"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Duration (weeks)</label>
                  <input
                    type="number"
                    min="1"
                    className="wwa-input"
                    value={addForm.durationWeeks}
                    onChange={e => setAddForm(prev => ({ ...prev, durationWeeks: e.target.value }))}
                    placeholder="e.g. 8"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Equipment</label>
                  <input
                    className="wwa-input"
                    value={addForm.equipment}
                    onChange={e => setAddForm(prev => ({ ...prev, equipment: e.target.value }))}
                    placeholder="Comma-separated, e.g. Barbell, Dumbbells, Bench"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Goals</label>
                  <input
                    className="wwa-input"
                    value={addForm.goals}
                    onChange={e => setAddForm(prev => ({ ...prev, goals: e.target.value }))}
                    placeholder="Comma-separated, e.g. Build Muscle, Build Strength"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Match Sport</label>
                  <input
                    className="wwa-input"
                    value={addForm.matchSport}
                    onChange={e => setAddForm(prev => ({ ...prev, matchSport: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Match Level</label>
                  <input
                    className="wwa-input"
                    value={addForm.matchLevel}
                    onChange={e => setAddForm(prev => ({ ...prev, matchLevel: e.target.value }))}
                  />
                </div>
                <div className="wwa-field-full">
                  <label className="wwa-field-label">Match Goals</label>
                  <input
                    className="wwa-input"
                    value={addForm.matchGoals}
                    onChange={e => setAddForm(prev => ({ ...prev, matchGoals: e.target.value }))}
                    placeholder="Comma-separated — feeds the Plan Match algorithm"
                  />
                </div>
                <div className="wwa-field-full">
                  <label className="wwa-field-label">Description</label>
                  <input
                    className="wwa-input"
                    value={addForm.description}
                    onChange={e => setAddForm(prev => ({ ...prev, description: e.target.value }))}
                    placeholder="Short description shown to users"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Image URL</label>
                  <input
                    className="wwa-input"
                    value={addForm.imageUrl}
                    onChange={e => setAddForm(prev => ({ ...prev, imageUrl: e.target.value }))}
                    placeholder="https://… (optional)"
                  />
                  {addForm.imageUrl.trim() && (
                    <div style={{ marginTop: 8 }}>
                      <ImageThumb url={addForm.imageUrl} size={56} icon="📋" />
                    </div>
                  )}
                </div>
                <div>
                  <label className="wwa-field-label">Status</label>
                  <div style={{ paddingTop: 8 }}>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#374151' }}>
                      <input
                        type="checkbox"
                        checked={addForm.isActive}
                        onChange={e => setAddForm(prev => ({ ...prev, isActive: e.target.checked }))}
                      />
                      Active (visible to users)
                    </label>
                  </div>
                </div>
              </div>

              <div className="wwa-panel-subtitle" style={{ marginTop: 4 }}>Designed By (optional)</div>
              <div className="wwa-form-grid">
                <div>
                  <label className="wwa-field-label">Name</label>
                  <input
                    className="wwa-input"
                    value={addForm.designedByName}
                    onChange={e => setAddForm(prev => ({ ...prev, designedByName: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Title</label>
                  <input
                    className="wwa-input"
                    value={addForm.designedByTitle}
                    onChange={e => setAddForm(prev => ({ ...prev, designedByTitle: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Credential</label>
                  <input
                    className="wwa-input"
                    value={addForm.designedByCredential}
                    onChange={e => setAddForm(prev => ({ ...prev, designedByCredential: e.target.value }))}
                  />
                </div>
                <div className="wwa-field-full">
                  <label className="wwa-field-label">Quote</label>
                  <input
                    className="wwa-input"
                    value={addForm.designedByQuote}
                    onChange={e => setAddForm(prev => ({ ...prev, designedByQuote: e.target.value }))}
                  />
                </div>
              </div>

              <div className="wwa-panel-subtitle" style={{ marginTop: 4 }}>Training Sessions (Week Schedule)</div>
              <PlanSessionsEditor
                sessions={addSessions}
                onChange={setAddSessions}
                exerciseCatalog={exerciseCatalog}
              />

              <div className="wwa-cell-actions" style={{ marginTop: 16 }}>
                <button className="wwa-btn wwa-btn-primary" onClick={handleAddPlan} disabled={addSaving}>
                  {addSaving ? 'Saving...' : 'Save Plan'}
                </button>
                <button
                  className="wwa-btn wwa-btn-secondary"
                  onClick={() => { setShowAddForm(false); setAddError(''); }}
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className={selectedPlan ? 'wwa-split-layout' : ''}>
          <div className={selectedPlan ? 'wwa-split-main' : ''}>
            <div className="wwa-toolbar">
              <div className="wwa-search">
                <input
                  className="wwa-input"
                  placeholder="Search plans…"
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                />
              </div>

              <select
                className="wwa-select wwa-select-inline"
                value={levelFilter}
                onChange={e => setLevelFilter(e.target.value)}
              >
                <option value="all">All Levels</option>
                {levels.map(l => (
                  <option key={l} value={l}>{l}</option>
                ))}
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={typeFilter}
                onChange={e => setTypeFilter(e.target.value)}
              >
                <option value="all">All Types</option>
                {types.map(t => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={sourceFilter}
                onChange={e => setSourceFilter(e.target.value)}
              >
                <option value="all">Source: All</option>
                <option value="official">Source: Official</option>
                <option value="custom">Source: Custom</option>
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={daysFilter}
                onChange={e => setDaysFilter(e.target.value)}
              >
                <option value="all">Days/Week: All</option>
                {daysOptions.map(d => (
                  <option key={d} value={d}>{d} days/week</option>
                ))}
              </select>

              <select
                className="wwa-select wwa-select-inline"
                value={statusFilter}
                onChange={e => setStatusFilter(e.target.value)}
              >
                <option value="all">Status: All</option>
                <option value="active">Status: Active</option>
                <option value="inactive">Status: Inactive</option>
              </select>

              <button className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={resetFilters}>
                Reset Filters
              </button>

              <span className="wwa-toolbar-count">{filtered.length} of {plans.length} plans</span>
            </div>

            <div className="wwa-table-wrap">
              <table className="wwa-table">
                <thead>
                  <tr>
                    {['Plan Name', 'Level', 'Duration', 'Days/Week', 'Equipment', 'Type', 'Source', 'Creator', 'Status', 'Action'].map(h => (
                      <th key={h}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filtered.length === 0 ? (
                    <tr>
                      <td colSpan="10" style={{ padding: 0, borderBottom: 'none' }}>
                        <EmptyState
                          icon="📋"
                          title="No plans found"
                          message={hasActiveFilters ? 'Try adjusting your search or filters.' : 'No plans in the library yet.'}
                        />
                      </td>
                    </tr>
                  ) : (
                    filtered.map(plan => (
                      <tr key={plan.id} className={selectedPlanId === plan.id ? 'wwa-row-selected' : ''}>
                        <td className="wwa-cell-primary">{plan.title || plan.name || '—'}</td>
                        <td>
                          <Badge tone={levelTone(plan.level)}>{plan.level || 'Beginner'}</Badge>
                        </td>
                        <td style={{ color: '#6b7280' }}>{plan.durationWeeks ? `${plan.durationWeeks} weeks` : '—'}</td>
                        <td style={{ color: '#6b7280' }}>{plan.daysPerWeek ? `${plan.daysPerWeek} days` : '—'}</td>
                        <td style={{ color: '#6b7280' }}>{formatEquipment(plan.equipment)}</td>
                        <td>
                          <Badge tone="brand">{plan.type || plan.category || 'General'}</Badge>
                        </td>
                        <td>
                          <Badge tone={plan.isCustom ? 'brand' : 'neutral'}>
                            {plan.isCustom ? 'Custom' : 'Official/System'}
                          </Badge>
                        </td>
                        <td style={{ color: '#6b7280' }}>{getCreatorLabel(plan)}</td>
                        <td>
                          <Badge tone={plan.isActive !== false ? 'success' : 'danger'}>
                            {plan.isActive !== false ? 'Active' : 'Inactive'}
                          </Badge>
                        </td>
                        <td>
                          <button
                            className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                            onClick={() => setSelectedPlanId(plan.id)}
                          >
                            View
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>

          {selectedPlan && (
            <div className="wwa-split-side wwa-split-side-wide">
              <PlanDetailPanel
                plan={selectedPlan}
                creatorLabel={getCreatorLabel(selectedPlan)}
                levelOptions={levelOptions}
                typeOptions={typeOptions}
                exerciseCatalog={exerciseCatalog}
                onClose={() => setSelectedPlanId(null)}
                onSave={handleSavePlan}
                onDelete={handleDeletePlan}
              />
            </div>
          )}
          </div>
        </>
      )}
    </div>
  );
}

export default Plans;
