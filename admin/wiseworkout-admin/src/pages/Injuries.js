import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, addDoc, updateDoc, deleteDoc, doc } from 'firebase/firestore';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import InjuryDetailPanel from '../components/InjuryDetailPanel';

const emptyForm = { name: '', bodyPart: '', description: '' };

function Injuries() {
  const [injuries, setInjuries] = useState([]);
  const [exercises, setExercises] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedInjuryId, setSelectedInjuryId] = useState(null);
  const [openInEdit, setOpenInEdit] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);
  const [addForm, setAddForm] = useState(emptyForm);
  const [addSaving, setAddSaving] = useState(false);
  const [addError, setAddError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  useEffect(() => {
    const fetchData = async () => {
      try {
        // Also loads exercises (read-only) so Delete can check for references
        // in exercise.injuryRisk before removing a category — see
        // countExercisesUsingInjury below.
        const [injurySnap, exercisesSnap] = await Promise.all([
          getDocs(collection(db, 'injuryCategories')),
          getDocs(collection(db, 'exercises')),
        ]);
        setInjuries(injurySnap.docs.map(d => ({ id: d.id, ...d.data() })));
        setExercises(exercisesSnap.docs.map(d => ({ id: d.id, ...d.data() })));
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchData();
  }, []);

  // Case-insensitive, matching how Exercises.js resolves/edits injuryRisk —
  // an exercise tagged "Lower back" still counts as using the "Lower Back" category.
  const countExercisesUsingInjury = (injuryName) => {
    const lower = (injuryName || '').toLowerCase();
    return exercises.filter(ex =>
      Array.isArray(ex.injuryRisk) && ex.injuryRisk.some(r => (r || '').toLowerCase() === lower)
    ).length;
  };

  const handleAddInjury = async () => {
    if (!addForm.name.trim()) { setAddError('Name is required.'); return; }
    if (!addForm.bodyPart.trim()) { setAddError('Body Part is required.'); return; }
    if (!addForm.description.trim()) { setAddError('Description is required.'); return; }

    setAddSaving(true);
    setAddError('');
    try {
      const payload = {
        name: addForm.name.trim(),
        bodyPart: addForm.bodyPart.trim(),
        description: addForm.description.trim(),
      };
      const docRef = await addDoc(collection(db, 'injuryCategories'), payload);
      setInjuries(prev => [...prev, { id: docRef.id, ...payload }]);
      setShowAddForm(false);
      setAddForm(emptyForm);
      setSuccessMsg('Injury category added successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setAddError('Failed to add injury category. Please try again.');
    }
    setAddSaving(false);
  };

  const handleSaveInjury = async (injuryId, changes) => {
    await updateDoc(doc(db, 'injuryCategories', injuryId), changes);
    setInjuries(prev => prev.map(i => i.id === injuryId ? { ...i, ...changes } : i));
  };

  const handleDeleteInjury = async (injuryId) => {
    const injury = injuries.find(i => i.id === injuryId);
    const usageCount = injury ? countExercisesUsingInjury(injury.name) : 0;
    if (usageCount > 0) {
      window.alert(
        `"${injury.name}" is currently used by ${usageCount} exercise${usageCount === 1 ? '' : 's'}. ` +
        'Remove this injury risk from those exercises before deleting the category.'
      );
      return;
    }
    if (!window.confirm('Are you sure you want to delete this injury category? This action cannot be undone.')) return;
    await deleteDoc(doc(db, 'injuryCategories', injuryId));
    setInjuries(prev => prev.filter(i => i.id !== injuryId));
    setSelectedInjuryId(prev => (prev === injuryId ? null : prev));
    setSuccessMsg('Injury category deleted successfully');
    setTimeout(() => setSuccessMsg(''), 3000);
  };

  const filtered = injuries.filter(i => {
    const q = search.toLowerCase();
    return !q ||
      (i.name || '').toLowerCase().includes(q) ||
      (i.bodyPart || '').toLowerCase().includes(q);
  });

  const selectedInjury = injuries.find(i => i.id === selectedInjuryId) || null;

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Injuries"
        subtitle={loading ? 'Loading injury categories…' : `${injuries.length} injury categories`}
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
              + Add Injury
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
              <div className="wwa-panel-title">New Injury Category</div>
              <div className="wwa-panel-subtitle">Fill in the injury category details below</div>

              {addError && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{addError}</div>}

              <div className="wwa-form-grid">
                <div>
                  <label className="wwa-field-label">Name</label>
                  <input
                    className="wwa-input"
                    value={addForm.name}
                    onChange={e => setAddForm(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="e.g. Lower Back"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Body Part</label>
                  <input
                    className="wwa-input"
                    value={addForm.bodyPart}
                    onChange={e => setAddForm(prev => ({ ...prev, bodyPart: e.target.value }))}
                    placeholder="e.g. Lower Back"
                  />
                </div>
                <div className="wwa-field-full">
                  <label className="wwa-field-label">Description</label>
                  <input
                    className="wwa-input"
                    value={addForm.description}
                    onChange={e => setAddForm(prev => ({ ...prev, description: e.target.value }))}
                    placeholder="e.g. Pain or discomfort in the lower back region"
                  />
                </div>
              </div>

              <div className="wwa-cell-actions">
                <button className="wwa-btn wwa-btn-primary" onClick={handleAddInjury} disabled={addSaving}>
                  {addSaving ? 'Saving...' : 'Save Injury'}
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

          <div className={selectedInjury ? 'wwa-split-layout' : ''}>
            <div className={selectedInjury ? 'wwa-split-main' : ''}>
              <div className="wwa-toolbar">
                <div className="wwa-search">
                  <input
                    className="wwa-input"
                    placeholder="Search by name or body part…"
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                  />
                </div>
                <span className="wwa-toolbar-count">{filtered.length} of {injuries.length} injury categories</span>
              </div>

              <div className="wwa-table-wrap">
                <table className="wwa-table">
                  <thead>
                    <tr>
                      {['Injury Name', 'Body Part', 'Description', 'Action'].map(h => (
                        <th key={h}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map(injury => (
                      <tr key={injury.id} className={selectedInjuryId === injury.id ? 'wwa-row-selected' : ''}>
                        <td className="wwa-cell-primary">{injury.name || '—'}</td>
                        <td style={{ color: '#6b7280' }}>{injury.bodyPart || '—'}</td>
                        <td style={{ color: '#6b7280' }}>{injury.description || '—'}</td>
                        <td>
                          <div className="wwa-cell-actions">
                            <button
                              className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                              onClick={() => { setSelectedInjuryId(injury.id); setOpenInEdit(false); }}
                            >
                              View
                            </button>
                            <button
                              className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                              onClick={() => { setSelectedInjuryId(injury.id); setOpenInEdit(true); }}
                            >
                              Edit
                            </button>
                            <button
                              className="wwa-btn wwa-btn-sm wwa-btn-danger"
                              onClick={() => handleDeleteInjury(injury.id)}
                            >
                              Delete
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {filtered.length === 0 && (
                  <EmptyState
                    icon="🩹"
                    title="No injury categories found"
                    message={search ? 'Try a different search term.' : 'No injury categories added yet.'}
                  />
                )}
              </div>
            </div>

            {selectedInjury && (
              <div className="wwa-split-side">
                <InjuryDetailPanel
                  injury={selectedInjury}
                  startInEdit={openInEdit}
                  onClose={() => setSelectedInjuryId(null)}
                  onSave={handleSaveInjury}
                  onDelete={handleDeleteInjury}
                />
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default Injuries;
