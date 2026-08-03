import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, addDoc, deleteDoc, doc, updateDoc } from 'firebase/firestore';
import * as XLSX from 'xlsx';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import TagListEditor from '../components/ui/TagListEditor';
import InstructionStepsEditor from '../components/InstructionStepsEditor';
import ExerciseDetailPanel from '../components/ExerciseDetailPanel';
import {
  formatInjuryRisk, formatSecondaryMuscles, formatRepRange, formatWeightRange,
  validateRepRange, validateWeightRange, cleanInstructionSteps, validateInstructionSteps,
  normalizeSecondaryMuscles,
} from '../utils/exerciseUtils';

const emptyForm = {
  name: '', difficulty: 'Beginner', equipment: '', muscle: '', muscleGroup: '',
  secondaryMuscles: [], injuryRisk: [], instructionSteps: [''],
  minReps: '', maxReps: '', minKg: '', maxKg: '', gifUrl: '',
};

const difficultyTone = (difficulty) =>
  difficulty === 'Advanced' ? 'danger' : difficulty === 'Intermediate' ? 'warning' : 'success';

function Exercises() {
  const [exercises, setExercises] = useState([]);
  const [injuryCategories, setInjuryCategories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [difficultyFilter, setDifficultyFilter] = useState('all');
  const [equipmentFilter, setEquipmentFilter] = useState('all');
  const [muscleGroupFilter, setMuscleGroupFilter] = useState('all');

  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(emptyForm);
  const [formError, setFormError] = useState('');
  const [saving, setSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');

  const [selectedExerciseId, setSelectedExerciseId] = useState(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [exercisesSnap, injurySnap] = await Promise.all([
          getDocs(collection(db, 'exercises')),
          getDocs(collection(db, 'injuryCategories')),
        ]);
        setExercises(exercisesSnap.docs.map(d => ({ id: d.id, ...d.data() })));
        setInjuryCategories(injurySnap.docs.map(d => ({ id: d.id, ...d.data() })));
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchData();
  }, []);

  // Checking a category dedupes any existing case-variant of its name before
  // appending the canonical one; unchecking removes every case-variant. Any
  // legacy value that doesn't match a current category is never touched by
  // either path, so it's preserved as-is rather than silently dropped.
  const toggleInjuryRisk = (categoryName) => {
    setForm(prev => {
      const lower = categoryName.toLowerCase();
      const already = prev.injuryRisk.some(v => (v || '').toLowerCase() === lower);
      const withoutVariants = prev.injuryRisk.filter(v => (v || '').toLowerCase() !== lower);
      return { ...prev, injuryRisk: already ? withoutVariants : [...withoutVariants, categoryName] };
    });
  };

  const handleAdd = async () => {
    if (!form.name.trim()) { setFormError('Exercise Name is required.'); return; }

    const stepsError = validateInstructionSteps(form.instructionSteps);
    if (stepsError) { setFormError(stepsError); return; }

    const minReps = Number(form.minReps);
    const maxReps = Number(form.maxReps);
    const repsError = validateRepRange(minReps, maxReps);
    if (repsError) { setFormError(repsError); return; }

    const minKg = Number(form.minKg);
    const maxKg = Number(form.maxKg);
    const weightError = validateWeightRange(minKg, maxKg);
    if (weightError) { setFormError(weightError); return; }

    const payload = {
      name: form.name.trim(),
      difficulty: form.difficulty,
      equipment: form.equipment.trim(),
      muscle: form.muscle.trim(),
      muscleGroup: form.muscleGroup.trim(),
      secondaryMuscles: normalizeSecondaryMuscles(form.secondaryMuscles, form.muscle),
      injuryRisk: form.injuryRisk,
      instructionSteps: cleanInstructionSteps(form.instructionSteps),
      minReps, maxReps, minKg, maxKg,
      gifUrl: form.gifUrl.trim() || null,
    };

    setSaving(true);
    setFormError('');
    try {
      if (editingId) {
        // updateDoc only touches the keys in `payload` — any field on the
        // document this form doesn't manage is left completely untouched.
        await updateDoc(doc(db, 'exercises', editingId), payload);
        setExercises(prev => prev.map(e => e.id === editingId ? { ...e, ...payload } : e));
        setEditingId(null);
      } else {
        const docRef = await addDoc(collection(db, 'exercises'), {
          ...payload,
          createdAt: new Date().toISOString(),
        });
        setExercises(prev => [...prev, { id: docRef.id, ...payload }]);
      }
      setForm(emptyForm);
      setShowForm(false);
      setSuccessMsg(editingId ? 'Exercise updated successfully' : 'Exercise added successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      setFormError(`Failed to save exercise. Please try again.${detail}`);
    }
    setSaving(false);
  };

  const handleEdit = (ex) => {
    setForm({
      name: ex.name || '',
      difficulty: ex.difficulty || 'Beginner',
      equipment: ex.equipment || '',
      muscle: ex.muscle || '',
      muscleGroup: ex.muscleGroup || '',
      secondaryMuscles: Array.isArray(ex.secondaryMuscles) ? [...ex.secondaryMuscles] : [],
      injuryRisk: Array.isArray(ex.injuryRisk) ? ex.injuryRisk : [],
      instructionSteps: Array.isArray(ex.instructionSteps) && ex.instructionSteps.length > 0
        ? [...ex.instructionSteps] : [''],
      minReps: ex.minReps ?? '',
      maxReps: ex.maxReps ?? '',
      minKg: ex.minKg ?? '',
      maxKg: ex.maxKg ?? '',
      gifUrl: ex.gifUrl || '',
    });
    setEditingId(ex.id);
    setFormError('');
    setShowForm(true);
  };

  // Plan sessions embed a standalone copy of each exercise (name/muscle/…),
  // not a reference to this document — see PlanSessionsEditor.js. So deleting
  // an exercise definition can never orphan or invalidate anything in a plan;
  // existing plan entries simply keep their own embedded historical copy.
  const handleDelete = async (id) => {
    if (!window.confirm('Delete this exercise?')) return;
    try {
      await deleteDoc(doc(db, 'exercises', id));
      setExercises(prev => prev.filter(e => e.id !== id));
      setSelectedExerciseId(prev => (prev === id ? null : prev));
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      window.alert(`Failed to delete exercise.${detail}`);
    }
  };

  const difficultyOptions = Array.from(new Set(exercises.map(e => e.difficulty).filter(Boolean))).sort();
  const equipmentOptions = Array.from(new Set(exercises.map(e => e.equipment).filter(Boolean))).sort();
  const muscleGroupOptions = Array.from(new Set(exercises.map(e => e.muscleGroup).filter(Boolean))).sort();

  const filtered = exercises.filter(e => {
    const q = search.toLowerCase();
    const matchesSearch =
      (e.name || '').toLowerCase().includes(q) ||
      (e.muscleGroup || '').toLowerCase().includes(q);
    const matchesDifficulty = difficultyFilter === 'all' || e.difficulty === difficultyFilter;
    const matchesEquipment = equipmentFilter === 'all' || e.equipment === equipmentFilter;
    const matchesMuscleGroup = muscleGroupFilter === 'all' || e.muscleGroup === muscleGroupFilter;
    return matchesSearch && matchesDifficulty && matchesEquipment && matchesMuscleGroup;
  });

  const selectedExercise = exercises.find(e => e.id === selectedExerciseId) || null;

  // Exports exactly the rows currently matching search/filters, as readable
  // text — arrays joined into comma-separated or numbered text, never raw JSON.
  const handleExport = () => {
    const rows = filtered.map(ex => ({
      'Exercise Name': ex.name || '—',
      Difficulty: ex.difficulty || 'Beginner',
      Equipment: ex.equipment || '—',
      'Primary Muscle': ex.muscle || '—',
      'Muscle Group': ex.muscleGroup || '—',
      'Secondary Muscles': formatSecondaryMuscles(ex.secondaryMuscles),
      'Injury Risk': formatInjuryRisk(ex.injuryRisk, injuryCategories),
      'Minimum Reps': ex.minReps ?? '—',
      'Maximum Reps': ex.maxReps ?? '—',
      'Minimum Weight (kg)': ex.minKg ?? '—',
      'Maximum Weight (kg)': ex.maxKg ?? '—',
      Instructions: Array.isArray(ex.instructionSteps) && ex.instructionSteps.length > 0
        ? ex.instructionSteps.map((s, i) => `${i + 1}. ${s}`).join('\n')
        : '—',
      'GIF URL': ex.gifUrl || '—',
    }));
    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 26 }, { wch: 12 }, { wch: 16 }, { wch: 16 }, { wch: 16 },
      { wch: 24 }, { wch: 26 }, { wch: 12 }, { wch: 12 }, { wch: 16 },
      { wch: 16 }, { wch: 50 }, { wch: 30 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Exercises');
    XLSX.writeFile(workbook, 'WiseWorkout_Exercises.xlsx');
  };

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Exercises"
        subtitle={loading ? 'Loading exercises…' : `${exercises.length} exercises in library`}
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
              onClick={() => { setShowForm(!showForm); setEditingId(null); setForm(emptyForm); setFormError(''); }}
            >
              + Add Exercise
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
          {showForm && (
            <div className="wwa-panel">
              <div className="wwa-panel-title">{editingId ? 'Edit Exercise' : 'New Exercise'}</div>
              <div className="wwa-panel-subtitle">Fill in the exercise details below</div>

              {formError && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{formError}</div>}

              <div className="wwa-form-grid">
                <div>
                  <label className="wwa-field-label">Exercise Name</label>
                  <input
                    className="wwa-input"
                    value={form.name}
                    onChange={e => setForm(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="e.g. Squat"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Difficulty</label>
                  <select
                    className="wwa-select"
                    value={form.difficulty}
                    onChange={e => setForm(prev => ({ ...prev, difficulty: e.target.value }))}
                  >
                    <option>Beginner</option>
                    <option>Intermediate</option>
                    <option>Advanced</option>
                  </select>
                </div>
                <div>
                  <label className="wwa-field-label">Equipment</label>
                  <input
                    className="wwa-input"
                    value={form.equipment}
                    onChange={e => setForm(prev => ({ ...prev, equipment: e.target.value }))}
                    placeholder="e.g. Barbell"
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Primary Muscle</label>
                  <input
                    className="wwa-input"
                    value={form.muscle}
                    onChange={e => setForm(prev => ({ ...prev, muscle: e.target.value }))}
                    placeholder="e.g. Legs"
                  />
                  <div style={{ fontSize: 11.5, color: '#9ca3af', marginTop: 4 }}>
                    The main muscle targeted by this exercise.
                  </div>
                </div>
                <div>
                  <label className="wwa-field-label">Muscle Group</label>
                  <input
                    className="wwa-input"
                    value={form.muscleGroup}
                    onChange={e => setForm(prev => ({ ...prev, muscleGroup: e.target.value }))}
                    placeholder="e.g. Thighs"
                  />
                  <div style={{ fontSize: 11.5, color: '#9ca3af', marginTop: 4 }}>
                    Used to classify exercises and support injury-based filtering.
                  </div>
                </div>
                <div>
                  <label className="wwa-field-label">GIF URL</label>
                  <input
                    className="wwa-input"
                    value={form.gifUrl}
                    onChange={e => setForm(prev => ({ ...prev, gifUrl: e.target.value }))}
                    placeholder="https://… (optional)"
                  />
                </div>
              </div>

              <div style={{ marginBottom: 16 }}>
                <label className="wwa-field-label">Secondary Muscles</label>
                <TagListEditor
                  tags={form.secondaryMuscles}
                  onChange={next => setForm(prev => ({ ...prev, secondaryMuscles: next }))}
                  disabled={saving}
                  placeholder="e.g. Glutes"
                />
              </div>

              <div className="wwa-form-grid" style={{ marginBottom: 4 }}>
                <div>
                  <label className="wwa-field-label">Minimum Reps</label>
                  <input
                    type="number" min="1" step="1"
                    className="wwa-input"
                    value={form.minReps}
                    onChange={e => setForm(prev => ({ ...prev, minReps: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Maximum Reps</label>
                  <input
                    type="number" min="1" step="1"
                    className="wwa-input"
                    value={form.maxReps}
                    onChange={e => setForm(prev => ({ ...prev, maxReps: e.target.value }))}
                  />
                </div>
              </div>
              <div style={{ fontSize: 11.5, color: '#9ca3af', marginTop: -10, marginBottom: 16 }}>
                These limits restrict the rep values users can record for this exercise.
              </div>

              <div className="wwa-form-grid" style={{ marginBottom: 4 }}>
                <div>
                  <label className="wwa-field-label">Minimum Weight (kg)</label>
                  <input
                    type="number" min="0" step="any"
                    className="wwa-input"
                    value={form.minKg}
                    onChange={e => setForm(prev => ({ ...prev, minKg: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="wwa-field-label">Maximum Weight (kg)</label>
                  <input
                    type="number" min="0" step="any"
                    className="wwa-input"
                    value={form.maxKg}
                    onChange={e => setForm(prev => ({ ...prev, maxKg: e.target.value }))}
                  />
                </div>
              </div>
              <div style={{ fontSize: 11.5, color: '#9ca3af', marginTop: -10, marginBottom: 16 }}>
                These limits restrict the weight values users can record for this exercise.
              </div>

              <div style={{ marginBottom: 16 }}>
                <label className="wwa-field-label">Injury Risks</label>
                {injuryCategories.length === 0 ? (
                  <div style={{ fontSize: 13, color: '#9ca3af' }}>
                    No injury categories yet — add some in the Injuries tab.
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
                    {injuryCategories.map(cat => {
                      const checked = form.injuryRisk.some(v => (v || '').toLowerCase() === (cat.name || '').toLowerCase());
                      return (
                        <label key={cat.id} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#374151' }}>
                          <input type="checkbox" checked={checked} onChange={() => toggleInjuryRisk(cat.name)} />
                          {cat.name}
                        </label>
                      );
                    })}
                  </div>
                )}
              </div>

              <div style={{ marginBottom: 16 }}>
                <InstructionStepsEditor
                  steps={form.instructionSteps}
                  onChange={next => setForm(prev => ({ ...prev, instructionSteps: next }))}
                  disabled={saving}
                />
              </div>

              <div className="wwa-cell-actions">
                <button className="wwa-btn wwa-btn-primary" onClick={handleAdd} disabled={saving}>
                  {saving ? 'Saving...' : editingId ? 'Update Exercise' : 'Save Exercise'}
                </button>
                <button
                  className="wwa-btn wwa-btn-secondary"
                  onClick={() => { setShowForm(false); setEditingId(null); setFormError(''); }}
                  disabled={saving}
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className={selectedExercise ? 'wwa-split-layout' : ''}>
            <div className={selectedExercise ? 'wwa-split-main' : ''}>
              <div className="wwa-toolbar">
                <div className="wwa-search">
                  <input
                    className="wwa-input"
                    placeholder="Search exercises…"
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                  />
                </div>
                <select className="wwa-select wwa-select-inline" value={difficultyFilter} onChange={e => setDifficultyFilter(e.target.value)}>
                  <option value="all">Difficulty: All</option>
                  {difficultyOptions.map(d => <option key={d} value={d}>{d}</option>)}
                </select>
                <select className="wwa-select wwa-select-inline" value={equipmentFilter} onChange={e => setEquipmentFilter(e.target.value)}>
                  <option value="all">Equipment: All</option>
                  {equipmentOptions.map(eq => <option key={eq} value={eq}>{eq}</option>)}
                </select>
                <select className="wwa-select wwa-select-inline" value={muscleGroupFilter} onChange={e => setMuscleGroupFilter(e.target.value)}>
                  <option value="all">Muscle Group: All</option>
                  {muscleGroupOptions.map(mg => <option key={mg} value={mg}>{mg}</option>)}
                </select>
                <span className="wwa-toolbar-count">{filtered.length} of {exercises.length} exercises</span>
              </div>

              <div className="wwa-table-wrap">
                <table className="wwa-table">
                  <thead>
                    <tr>
                      {[
                        'Exercise Name', 'Difficulty', 'Equipment', 'Primary Muscle', 'Muscle Group',
                        'Secondary Muscles', 'Injury Risk', 'Rep Range', 'Weight Range', 'Action',
                      ].map(h => <th key={h}>{h}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map(ex => (
                      <tr key={ex.id} className={selectedExerciseId === ex.id ? 'wwa-row-selected' : ''}>
                        <td className="wwa-cell-primary">{ex.name || '—'}</td>
                        <td>
                          <Badge tone={difficultyTone(ex.difficulty)}>{ex.difficulty || 'Beginner'}</Badge>
                        </td>
                        <td style={{ color: '#6b7280' }}>{ex.equipment || '—'}</td>
                        <td style={{ color: '#6b7280' }}>{ex.muscle || '—'}</td>
                        <td style={{ color: '#6b7280' }}>{ex.muscleGroup || '—'}</td>
                        <td style={{ color: '#6b7280' }}>{formatSecondaryMuscles(ex.secondaryMuscles)}</td>
                        <td style={{ color: '#6b7280' }}>{formatInjuryRisk(ex.injuryRisk, injuryCategories)}</td>
                        <td style={{ color: '#6b7280' }}>{formatRepRange(ex.minReps, ex.maxReps)}</td>
                        <td style={{ color: '#6b7280' }}>{formatWeightRange(ex.minKg, ex.maxKg)}</td>
                        <td>
                          <div className="wwa-cell-actions">
                            <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={() => setSelectedExerciseId(ex.id)}>
                              View
                            </button>
                            <button className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={() => handleEdit(ex)}>
                              Edit
                            </button>
                            <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => handleDelete(ex.id)}>
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
                    icon="💪"
                    title="No exercises found"
                    message={search ? 'Try a different search term.' : 'No exercises in the library yet.'}
                  />
                )}
              </div>
            </div>

            {selectedExercise && (
              <div className="wwa-split-side">
                <ExerciseDetailPanel
                  exercise={selectedExercise}
                  injuryCategories={injuryCategories}
                  onClose={() => setSelectedExerciseId(null)}
                />
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default Exercises;
