import React, { useState, useEffect } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import ChallengeCategoryDetailPanel from '../components/ChallengeCategoryDetailPanel';
import ChallengeDetailPanel from '../components/ChallengeDetailPanel';
import {
  METRIC_TYPES, validateCategoryForm, resolveCategoryDisplay, formatGoal, computeChallengeStatus,
} from '../utils/challengeUtils';
import { formatDate } from '../utils/dateUtils';

const emptyCategoryForm = { name: '', unit: '', metricType: METRIC_TYPES[0], minGoal: '', maxGoal: '' };
const emptyChallengeForm = { name: '', categoryId: '', goalValue: '', startDate: '', endDate: '' };

const statusTone = (status) => status === 'Active' ? 'success' : status === 'Upcoming' ? 'brand' : status === 'Ended' ? 'neutral' : 'neutral';

function Challenges() {
  const [challenges, setChallenges] = useState([]);
  const [categories, setCategories] = useState([]);
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
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

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
  
      try {
        const adminListChallengeDashboard = httpsCallable(
          functions,
          'adminListChallengeDashboard'
        );
  
        const result = await adminListChallengeDashboard();
        const data = result.data || {};
  
        setChallenges(
          Array.isArray(data.challenges) ? data.challenges : []
        );
  
        setCategories(
          Array.isArray(data.categories) ? data.categories : []
        );
  
        setUsers(
          Array.isArray(data.users) ? data.users : []
        );
      } catch (err) {
        console.error('Failed to load challenge dashboard:', err);
        window.alert(
          `Failed to load challenge dashboard.${
            err?.code ? ` (${err.code})` : ''
          }`
        );
      } finally {
        setLoading(false);
      }
    };
  
    fetchData();
  }, []);

  // ── Categories ──────────────────────────────────────────────────────────

  const countChallengesUsingCategory = (categoryId) =>
    challenges.filter(c => c.categoryId === categoryId).length;

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
    
        const adminCreateChallengeCategory = httpsCallable(
          functions,
          'adminCreateChallengeCategory'
        );
    
        const result = await adminCreateChallengeCategory({
          category: payload,
        });
    
        setCategories(prev => [
          ...prev,
          {
            id: result.data.categoryId,
            ...(result.data.category || payload),
          },
        ]);
    
        setShowAddCategoryForm(false);
        setAddCategoryForm(emptyCategoryForm);
        setCategorySuccessMsg('Category added successfully');
        setTimeout(() => setCategorySuccessMsg(''), 3000);
      } catch (err) {
        console.error(err);
    
        const detail = err?.code ? ` (${err.code})` : '';
    
        setAddCategoryError(
          `Failed to add category. Please try again.${detail}`
        );
      } finally {
        setAddCategorySaving(false);
      }
    };

    const handleSaveCategory = async (categoryId, changes) => {
      const adminUpdateChallengeCategory = httpsCallable(
        functions,
        'adminUpdateChallengeCategory'
      );
    
      const result = await adminUpdateChallengeCategory({
        categoryId,
        changes,
      });
    
      const savedCategory = result.data.category || changes;
    
      setCategories(prev =>
        prev.map(category =>
          category.id === categoryId
            ? { ...category, ...savedCategory }
            : category
        )
      );
    };

    const handleDeleteCategory = async (categoryId) => {
      const usageCount = countChallengesUsingCategory(categoryId);
    
      if (usageCount > 0) {
        window.alert(
          `This category is currently used by ${usageCount} ` +
          `challenge${usageCount === 1 ? '' : 's'}. ` +
          'Delete those challenges before removing the category.'
        );
        return;
      }
    
      const category = categories.find(item => item.id === categoryId);
      const categoryName = category?.name || categoryId;
    
      const confirmation = window.prompt(
        `Permanently delete category "${categoryName}"?\n\n` +
        'Type DELETE to continue:'
      );
    
      if (confirmation !== 'DELETE') return;
    
      try {
        const adminDeleteChallengeCategory = httpsCallable(
          functions,
          'adminDeleteChallengeCategory'
        );
    
        await adminDeleteChallengeCategory({
          categoryId,
        });
    
        setCategories(prev =>
          prev.filter(item => item.id !== categoryId)
        );
    
        setSelectedCategoryId(prev =>
          prev === categoryId ? null : prev
        );
    
        setCategorySuccessMsg('Category deleted successfully');
        setTimeout(() => setCategorySuccessMsg(''), 3000);
      } catch (err) {
        console.error(err);
    
        const detail = err?.code ? ` (${err.code})` : '';
    
        window.alert(`Failed to delete category.${detail}`);
      }
    };

  const selectedCategory = categories.find(c => c.id === selectedCategoryId) || null;

  // Global challenge management uses secure callable Cloud Functions.
  // Private challenges remain user-owned and read-only in the admin portal.

  const selectedChallengeCategory = categories.find(c => c.id === addChallengeForm.categoryId) || null;

  const handleAddChallenge = async () => {
    if (!addChallengeForm.name.trim()) {
      setAddChallengeError('Challenge Name is required.');
      return;
    }
  
    const category = categories.find(
      item => item.id === addChallengeForm.categoryId
    );
  
    if (!category) {
      setAddChallengeError('Select a category.');
      return;
    }
  
    const goalValue = Number(addChallengeForm.goalValue);
  
    if (
      addChallengeForm.goalValue === '' ||
      !Number.isFinite(goalValue)
    ) {
      setAddChallengeError('Goal Value must be a valid number.');
      return;
    }
  
    if (
      goalValue < category.minGoal ||
      goalValue > category.maxGoal
    ) {
      setAddChallengeError(
        `Goal Value must be between ${category.minGoal} and ` +
        `${category.maxGoal} ${category.unit}.`
      );
      return;
    }
  
    if (!addChallengeForm.startDate) {
      setAddChallengeError('Start Date is required.');
      return;
    }
  
    if (!addChallengeForm.endDate) {
      setAddChallengeError('End Date is required.');
      return;
    }
  
    const startDateObj = new Date(addChallengeForm.startDate);
    const endDateObj = new Date(addChallengeForm.endDate);
  
    if (
      Number.isNaN(startDateObj.getTime()) ||
      Number.isNaN(endDateObj.getTime())
    ) {
      setAddChallengeError(
        'Start Date and End Date must be valid dates.'
      );
      return;
    }
  
    if (endDateObj <= startDateObj) {
      setAddChallengeError('End Date must be after Start Date.');
      return;
    }
  
    setAddChallengeSaving(true);
    setAddChallengeError('');
  
    try {
      const adminCreateGlobalChallenge = httpsCallable(
        functions,
        'adminCreateGlobalChallenge'
      );
  
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
  
      setChallenges(prev => [
        ...prev,
        {
          id: result.data.challengeId,
          ...savedChallenge,
        },
      ]);
  
      setShowAddChallengeForm(false);
      setAddChallengeForm(emptyChallengeForm);
      setChallengeSuccessMsg(
        'Global challenge created successfully'
      );
      setTimeout(() => setChallengeSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
  
      const detail = err?.code ? ` (${err.code})` : '';
  
      setAddChallengeError(
        `Failed to create challenge. Please try again.${detail}`
      );
    } finally {
      setAddChallengeSaving(false);
    }
  };

  const handleDeleteChallenge = async (challenge) => {
  if (challenge.isGlobal !== true) {
    window.alert(
      'Private challenges are owned by users and cannot be deleted ' +
      'from the admin dashboard.'
    );
    return;
  }

  const participantCount = Array.isArray(challenge.participantUids)
    ? challenge.participantUids.length
    : 0;

  if (participantCount > 0) {
    window.alert(
      'This global challenge already has participants and cannot be ' +
      'deleted.'
    );
    return;
  }

  const challengeName =
    challenge.name || challenge.title || challenge.id;

  const confirmation = window.prompt(
    `Permanently delete global challenge "${challengeName}"?\n\n` +
    'Type DELETE to continue:'
  );

  if (confirmation !== 'DELETE') return;

  try {
    const adminDeleteChallenge = httpsCallable(
      functions,
      'adminDeleteChallenge'
    );

    await adminDeleteChallenge({
      challengeId: challenge.id,
    });

    setChallenges(prev =>
      prev.filter(item => item.id !== challenge.id)
    );

    setSelectedChallengeId(prev =>
      prev === challenge.id ? null : prev
    );

    setChallengeSuccessMsg(
      'Global challenge deleted successfully'
    );
    setTimeout(() => setChallengeSuccessMsg(''), 3000);
  } catch (err) {
    console.error(err);

    const detail = err?.code ? ` (${err.code})` : '';

    window.alert(`Failed to delete challenge.${detail}`);
  }
};

  const filteredChallenges = challenges.filter(c =>
    (c.title || c.name || '').toLowerCase().includes(search.toLowerCase())
  );

  const selectedChallenge = challenges.find(c => c.id === selectedChallengeId) || null;

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Challenges"
        subtitle={loading ? 'Loading challenges…' : 'Manage challenge categories and global challenges'}
      />

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <>
          {/* ── Challenge Categories ─────────────────────────────────── */}
          <div className="wwa-panel">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 4, gap: 12, flexWrap: 'wrap' }}>
              <div>
                <div className="wwa-panel-title">Challenge Categories</div>
                <div className="wwa-panel-subtitle">Metric categories used by global challenges</div>
              </div>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                {categorySuccessMsg && (
                  <span className="wwa-status-pill">
                    <span className="wwa-status-dot" />
                    {categorySuccessMsg}
                  </span>
                )}
                <button
                  className="wwa-btn wwa-btn-sm wwa-btn-primary"
                  onClick={() => { setShowAddCategoryForm(!showAddCategoryForm); setAddCategoryError(''); setAddCategoryForm(emptyCategoryForm); }}
                >
                  + Add Category
                </button>
              </div>
            </div>

            {showAddCategoryForm && (
              <div style={{ marginTop: 16, paddingTop: 16, borderTop: '1px solid #f3f4f6' }}>
                {addCategoryError && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{addCategoryError}</div>}
                <div className="wwa-form-grid">
                  <div>
                    <label className="wwa-field-label">Category Name</label>
                    <input
                      className="wwa-input"
                      value={addCategoryForm.name}
                      onChange={e => setAddCategoryForm(prev => ({ ...prev, name: e.target.value }))}
                      placeholder="e.g. Distance"
                    />
                  </div>
                  <div>
                    <label className="wwa-field-label">Unit</label>
                    <input
                      className="wwa-input"
                      value={addCategoryForm.unit}
                      onChange={e => setAddCategoryForm(prev => ({ ...prev, unit: e.target.value }))}
                      placeholder="e.g. km"
                    />
                  </div>
                  <div>
                    <label className="wwa-field-label">Metric Type</label>
                    <select
                      className="wwa-select"
                      value={addCategoryForm.metricType}
                      onChange={e => setAddCategoryForm(prev => ({ ...prev, metricType: e.target.value }))}
                    >
                      {METRIC_TYPES.map(mt => <option key={mt} value={mt}>{mt}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="wwa-field-label">Minimum Goal</label>
                    <input
                      type="number"
                      min="0"
                      className="wwa-input"
                      value={addCategoryForm.minGoal}
                      onChange={e => setAddCategoryForm(prev => ({ ...prev, minGoal: e.target.value }))}
                    />
                  </div>
                  <div>
                    <label className="wwa-field-label">Maximum Goal</label>
                    <input
                      type="number"
                      min="0"
                      className="wwa-input"
                      value={addCategoryForm.maxGoal}
                      onChange={e => setAddCategoryForm(prev => ({ ...prev, maxGoal: e.target.value }))}
                    />
                  </div>
                </div>
                <div className="wwa-cell-actions" style={{ marginTop: 16 }}>
                  <button className="wwa-btn wwa-btn-primary" onClick={handleAddCategory} disabled={addCategorySaving}>
                    {addCategorySaving ? 'Saving...' : 'Save Category'}
                  </button>
                  <button
                    className="wwa-btn wwa-btn-secondary"
                    onClick={() => { setShowAddCategoryForm(false); setAddCategoryError(''); }}
                    disabled={addCategorySaving}
                  >
                    Cancel
                  </button>
                </div>
              </div>
            )}

            <div className={selectedCategory ? 'wwa-split-layout' : ''} style={{ marginTop: 16 }}>
              <div className={selectedCategory ? 'wwa-split-main' : ''}>
                <div className="wwa-table-wrap">
                  <table className="wwa-table">
                    <thead>
                      <tr>
                        {['Name', 'Unit', 'Metric Type', 'Min Goal', 'Max Goal', 'Action'].map(h => (
                          <th key={h}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {categories.map(category => (
                        <tr key={category.id} className={selectedCategoryId === category.id ? 'wwa-row-selected' : ''}>
                          <td className="wwa-cell-primary">{category.name || '—'}</td>
                          <td style={{ color: '#6b7280' }}>{category.unit || '—'}</td>
                          <td><Badge tone="neutral">{category.metricType || '—'}</Badge></td>
                          <td style={{ color: '#6b7280' }}>{category.minGoal ?? '—'}</td>
                          <td style={{ color: '#6b7280' }}>{category.maxGoal ?? '—'}</td>
                          <td>
                            <div className="wwa-cell-actions">
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                                onClick={() => { setSelectedCategoryId(category.id); setOpenCategoryInEdit(false); }}
                              >
                                View
                              </button>
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                                onClick={() => { setSelectedCategoryId(category.id); setOpenCategoryInEdit(true); }}
                              >
                                Edit
                              </button>
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-danger"
                                onClick={() => handleDeleteCategory(category.id)}
                              >
                                Delete
                              </button>
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {categories.length === 0 && (
                    <EmptyState icon="🏷️" title="No categories yet" message="Add a category to get started." />
                  )}
                </div>
              </div>

              {selectedCategory && (
                <div className="wwa-split-side">
                  <ChallengeCategoryDetailPanel
                    category={selectedCategory}
                    startInEdit={openCategoryInEdit}
                    usageCount={countChallengesUsingCategory(selectedCategory.id)}
                    onClose={() => setSelectedCategoryId(null)}
                    onSave={handleSaveCategory}
                    onDelete={handleDeleteCategory}
                  />
                </div>
              )}
            </div>
          </div>

          {/* ── Challenges ───────────────────────────────────────────── */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 4, gap: 12, flexWrap: 'wrap' }}>
            <div>
              <div className="wwa-panel-title">Challenges</div>
              <div className="wwa-panel-subtitle">
                {challenges.length} challenge{challenges.length === 1 ? '' : 's'} on the platform
              </div>
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              {challengeSuccessMsg && (
                <span className="wwa-status-pill">
                  <span className="wwa-status-dot" />
                  {challengeSuccessMsg}
                </span>
              )}
              <button
                className="wwa-btn wwa-btn-sm wwa-btn-primary"
                onClick={() => { setShowAddChallengeForm(!showAddChallengeForm); setAddChallengeError(''); setAddChallengeForm(emptyChallengeForm); }}
                disabled={categories.length === 0}
                title={categories.length === 0 ? 'Add a challenge category first' : undefined}
              >
                + Add Global Challenge
              </button>
            </div>
          </div>

          {showAddChallengeForm && (
            <div className="wwa-panel">
              <div className="wwa-panel-title">New Global Challenge</div>
              <div className="wwa-panel-subtitle">
                Always created as isGlobal: true, createdBy: "admin", with empty participantUids/invitedUids —
                users join through the app.
              </div>

              {addChallengeError && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{addChallengeError}</div>}

              <div className="wwa-form-grid">
                <div>
                  <label className="wwa-field-label">Challenge Name</label>
                  <input
                    className="wwa-input"
                    value={addChallengeForm.name}
                    onChange={e => setAddChallengeForm(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="e.g. April Distance Challenge"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Category</label>
                  <select
                    className="wwa-select"
                    value={addChallengeForm.categoryId}
                    onChange={e => setAddChallengeForm(prev => ({ ...prev, categoryId: e.target.value }))}
                  >
                    <option value="">Select a category…</option>
                    {categories.map(c => (
                      <option key={c.id} value={c.id}>{c.name} ({c.metricType})</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="wwa-field-label">Goal Value</label>
                  <input
                    type="number"
                    className="wwa-input"
                    value={addChallengeForm.goalValue}
                    onChange={e => setAddChallengeForm(prev => ({ ...prev, goalValue: e.target.value }))}
                    placeholder={selectedChallengeCategory ? `${selectedChallengeCategory.minGoal}–${selectedChallengeCategory.maxGoal}` : 'e.g. 50'}
                  />
                  {selectedChallengeCategory && (
                    <div style={{ fontSize: 11.5, color: '#9ca3af', marginTop: 4 }}>
                      Allowed range: {selectedChallengeCategory.minGoal}–{selectedChallengeCategory.maxGoal} {selectedChallengeCategory.unit}
                    </div>
                  )}
                </div>
                <div>
                  <label className="wwa-field-label">Start Date</label>
                  <input
                    type="datetime-local"
                    className="wwa-input"
                    value={addChallengeForm.startDate}
                    onChange={e => setAddChallengeForm(prev => ({ ...prev, startDate: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="wwa-field-label">End Date</label>
                  <input
                    type="datetime-local"
                    className="wwa-input"
                    value={addChallengeForm.endDate}
                    onChange={e => setAddChallengeForm(prev => ({ ...prev, endDate: e.target.value }))}
                  />
                </div>
              </div>

              {(addChallengeForm.startDate || addChallengeForm.endDate) && (
                <div style={{ fontSize: 12.5, color: '#6b7280', marginBottom: 16 }}>
                  {addChallengeForm.startDate && !Number.isNaN(new Date(addChallengeForm.startDate).getTime()) && (
                    <div>Start: {new Date(addChallengeForm.startDate).toLocaleString()}</div>
                  )}
                  {addChallengeForm.endDate && !Number.isNaN(new Date(addChallengeForm.endDate).getTime()) && (
                    <div>End: {new Date(addChallengeForm.endDate).toLocaleString()}</div>
                  )}
                </div>
              )}

              <div className="wwa-cell-actions">
                <button className="wwa-btn wwa-btn-primary" onClick={handleAddChallenge} disabled={addChallengeSaving}>
                  {addChallengeSaving ? 'Saving...' : 'Save Challenge'}
                </button>
                <button
                  className="wwa-btn wwa-btn-secondary"
                  onClick={() => { setShowAddChallengeForm(false); setAddChallengeError(''); }}
                  disabled={addChallengeSaving}
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className={selectedChallenge ? 'wwa-split-layout' : ''}>
            <div className={selectedChallenge ? 'wwa-split-main' : ''}>
              <div className="wwa-toolbar">
                <div className="wwa-search">
                  <input
                    className="wwa-input"
                    placeholder="Search challenges…"
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                  />
                </div>
                <span className="wwa-toolbar-count">{filteredChallenges.length} of {challenges.length} challenges</span>
              </div>

              <div className="wwa-table-wrap">
                <table className="wwa-table">
                  <thead>
                    <tr>
                      {['Name', 'Category', 'Goal', 'Start Date', 'End Date', 'Type', 'Participants', 'Status', 'Action'].map(h => (
                        <th key={h}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {filteredChallenges.map(challenge => {
                      const categoryDisplay = resolveCategoryDisplay(challenge.categoryId, categories);
                      const isGlobal = challenge.isGlobal === true;
                      const status = computeChallengeStatus(challenge.startDate, challenge.endDate);
                      return (
                        <tr key={challenge.id} className={selectedChallengeId === challenge.id ? 'wwa-row-selected' : ''}>
                          <td className="wwa-cell-primary">{challenge.name || challenge.title || '—'}</td>
                          <td>
                            {categoryDisplay.missing
                              ? <span style={{ color: '#cc8800' }}>⚠ {categoryDisplay.text}</span>
                              : <span style={{ color: '#6b7280' }}>{categoryDisplay.text}</span>}
                          </td>
                          <td style={{ color: '#6b7280' }}>{formatGoal(challenge, categories)}</td>
                          <td style={{ color: '#6b7280' }}>{formatDate(challenge.startDate)}</td>
                          <td style={{ color: '#6b7280' }}>{formatDate(challenge.endDate)}</td>
                          <td><Badge tone={isGlobal ? 'brand' : 'neutral'}>{isGlobal ? 'Global' : 'Private'}</Badge></td>
                          <td style={{ color: '#6b7280' }}>
                            {Array.isArray(challenge.participantUids) ? challenge.participantUids.length : 0}
                          </td>
                          <td><Badge tone={statusTone(status)}>{status}</Badge></td>
                          <td>
                            <div className="wwa-cell-actions">
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                                onClick={() => setSelectedChallengeId(challenge.id)}
                              >
                                View
                              </button>
                              {challenge.isGlobal === true ? (
                                <button
                                  className="wwa-btn wwa-btn-sm wwa-btn-danger"
                                  onClick={() => handleDeleteChallenge(challenge)}
                                >
                                  Delete
                                </button>
                              ) : (
                                <span style={{ fontSize: 12, color: '#9ca3af' }}>
                                  User-owned
                                </span>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
                {filteredChallenges.length === 0 && (
                  <EmptyState
                    icon="🏆"
                    title="No challenges found"
                    message={search ? 'Try a different search term.' : 'No challenges on the platform yet.'}
                  />
                )}
              </div>
            </div>

            {selectedChallenge && (
              <div className="wwa-split-side">
                <ChallengeDetailPanel
                  challenge={selectedChallenge}
                  categories={categories}
                  users={users}
                  onClose={() => setSelectedChallengeId(null)}
                  onDelete={handleDeleteChallenge}
                />
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default Challenges;
