import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, addDoc, updateDoc, deleteDoc, doc } from 'firebase/firestore';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import ImageThumb from '../components/ui/ImageThumb';
import ConditionsEditor from '../components/ConditionsEditor';
import BadgeDetailPanel from '../components/BadgeDetailPanel';
import { formatConditions, validateConditions, normalizeConditionsForSave, isValidImageUrl } from '../utils/badgeUtils';

const emptyForm = { name: '', description: '', imageUrl: '', conditions: [{ statType: '', value: '' }] };

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

  useEffect(() => {
    const fetchBadges = async () => {
      try {
        const snap = await getDocs(collection(db, 'badges'));
        setBadges(snap.docs.map(d => ({ id: d.id, ...d.data() })));
      } catch (err) {
        console.error(err);
        const detail = err && err.code ? ` (${err.code})` : '';
        setLoadError(`Failed to load badges.${detail}`);
      }
      setLoading(false);
    };
    fetchBadges();
  }, []);

  const handleAddBadge = async () => {
    if (!addForm.name.trim()) { setAddError('Badge Name is required.'); return; }
    if (!addForm.description.trim()) { setAddError('Description is required.'); return; }
    if (addForm.imageUrl.trim() && !isValidImageUrl(addForm.imageUrl)) {
      setAddError('Image URL must start with http:// or https://.');
      return;
    }
    const conditionsError = validateConditions(addForm.conditions);
    if (conditionsError) { setAddError(conditionsError); return; }

    setAddSaving(true);
    setAddError('');
    try {
      const payload = {
        name: addForm.name.trim(),
        description: addForm.description.trim(),
        imageUrl: addForm.imageUrl.trim(),
        conditions: normalizeConditionsForSave(addForm.conditions),
      };
      const docRef = await addDoc(collection(db, 'badges'), payload);
      setBadges(prev => [...prev, { id: docRef.id, ...payload }]);
      setShowAddForm(false);
      setAddForm(emptyForm);
      setSuccessMsg('Badge added successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      setAddError(`Failed to add badge. Please try again.${detail}`);
    }
    setAddSaving(false);
  };

  // Partial update via the badge's existing document ID — never replaces
  // the whole document.
  const handleSaveBadge = async (badgeId, changes) => {
    await updateDoc(doc(db, 'badges', badgeId), changes);
    setBadges(prev => prev.map(b => b.id === badgeId ? { ...b, ...changes } : b));
  };

  // Deletes only the badge definition doc — users/{uid}/earnedBadges records
  // (if any exist) are never touched here; no cleanup logic for them exists
  // anywhere in this app today.
  const handleDeleteBadge = async (badgeId) => {
    if (!window.confirm('Are you sure you want to permanently delete this badge? This action cannot be undone.')) return;
    try {
      await deleteDoc(doc(db, 'badges', badgeId));
      setBadges(prev => prev.filter(b => b.id !== badgeId));
      setSelectedBadgeId(prev => (prev === badgeId ? null : prev));
      setSuccessMsg('Badge deleted successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      window.alert(`Failed to delete badge.${detail}`);
    }
  };

  const filtered = badges.filter(b => {
    const q = search.toLowerCase();
    if (!q) return true;
    const matchesBasic =
      (b.name || '').toLowerCase().includes(q) ||
      (b.description || '').toLowerCase().includes(q);
    const matchesStat = Array.isArray(b.conditions) &&
      b.conditions.some(c => (c?.statType || '').toLowerCase().includes(q));
    return matchesBasic || matchesStat;
  });

  const selectedBadge = badges.find(b => b.id === selectedBadgeId) || null;

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Badges"
        subtitle={loading ? 'Loading badges…' : 'Manage achievement badges and their earning conditions.'}
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
              onClick={() => { setShowAddForm(!showAddForm); setAddError(''); setAddForm(emptyForm); }}
            >
              + Add Badge
            </button>
          </>
        )}
      />

      {!loading && loadError && (
        <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{loadError}</div>
      )}

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <>
          {showAddForm && (
            <div className="wwa-panel">
              <div className="wwa-panel-title">New Badge</div>
              <div className="wwa-panel-subtitle">Fill in the badge details and its earning conditions</div>

              {addError && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{addError}</div>}

              <div className="wwa-form-grid" style={{ marginBottom: 16 }}>
                <div>
                  <label className="wwa-field-label">Badge Name</label>
                  <input
                    className="wwa-input"
                    value={addForm.name}
                    onChange={e => setAddForm(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="e.g. Distance Runner"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Image URL</label>
                  <input
                    className="wwa-input"
                    value={addForm.imageUrl}
                    onChange={e => setAddForm(prev => ({ ...prev, imageUrl: e.target.value }))}
                    placeholder="https://…"
                  />
                </div>
                <div className="wwa-field-full">
                  <label className="wwa-field-label">Description</label>
                  <input
                    className="wwa-input"
                    value={addForm.description}
                    onChange={e => setAddForm(prev => ({ ...prev, description: e.target.value }))}
                    placeholder="e.g. Run 50km total"
                  />
                </div>
              </div>

              <ConditionsEditor
                conditions={addForm.conditions}
                onChange={next => setAddForm(prev => ({ ...prev, conditions: next }))}
                disabled={addSaving}
              />

              <div className="wwa-cell-actions" style={{ marginTop: 16 }}>
                <button className="wwa-btn wwa-btn-primary" onClick={handleAddBadge} disabled={addSaving}>
                  {addSaving ? 'Saving...' : 'Save Badge'}
                </button>
                <button
                  className="wwa-btn wwa-btn-secondary"
                  onClick={() => { setShowAddForm(false); setAddError(''); }}
                  disabled={addSaving}
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className={selectedBadge ? 'wwa-split-layout' : ''}>
            <div className={selectedBadge ? 'wwa-split-main' : ''}>
              <div className="wwa-toolbar">
                <div className="wwa-search">
                  <input
                    className="wwa-input"
                    placeholder="Search by name, description, or stat type…"
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                  />
                </div>
                <span className="wwa-toolbar-count">{filtered.length} of {badges.length} badges</span>
              </div>

              <div className="wwa-table-wrap">
                <table className="wwa-table">
                  <thead>
                    <tr>
                      {['Badge', 'Description', 'Condition', 'Image', 'Action'].map(h => (
                        <th key={h}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map(badge => {
                      const conditionTexts = formatConditions(badge.conditions);
                      return (
                        <tr key={badge.id} className={selectedBadgeId === badge.id ? 'wwa-row-selected' : ''}>
                          <td>
                            <div className="wwa-cell-primary">{badge.name || 'Unnamed badge'}</div>
                            <div className="wwa-cell-muted">{badge.id}</div>
                          </td>
                          <td style={{ color: '#6b7280' }}>{badge.description || '—'}</td>
                          <td style={{ color: '#6b7280' }}>
                            {conditionTexts === '—'
                              ? '—'
                              : conditionTexts.map((text, i) => <div key={i}>{text}</div>)}
                          </td>
                          <td>
                            <ImageThumb url={badge.imageUrl} />
                          </td>
                          <td>
                            <div className="wwa-cell-actions">
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                                onClick={() => { setSelectedBadgeId(badge.id); setOpenInEdit(false); }}
                              >
                                View
                              </button>
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                                onClick={() => { setSelectedBadgeId(badge.id); setOpenInEdit(true); }}
                              >
                                Edit
                              </button>
                              <button
                                className="wwa-btn wwa-btn-sm wwa-btn-danger"
                                onClick={() => handleDeleteBadge(badge.id)}
                              >
                                Delete
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
                {filtered.length === 0 && (
                  <EmptyState
                    icon="🏅"
                    title="No badges found"
                    message={search ? 'Try a different search term.' : 'No badges added yet.'}
                  />
                )}
              </div>
            </div>

            {selectedBadge && (
              <div className="wwa-split-side">
                <BadgeDetailPanel
                  badge={selectedBadge}
                  startInEdit={openInEdit}
                  onClose={() => setSelectedBadgeId(null)}
                  onSave={handleSaveBadge}
                  onDelete={handleDeleteBadge}
                />
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default Badges;
