import React, { useEffect, useMemo, useState } from 'react';
import { collection, getDocs } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import { Download, Eye, Pencil, Plus, Trash2 } from 'lucide-react';
import { db, functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import TagListEditor from '../components/ui/TagListEditor';
import InstructionStepsEditor from '../components/InstructionStepsEditor';
import ExerciseDetailPanel from '../components/ExerciseDetailPanel';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import SelectField from '../components/ui/SelectField';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import DataTable from '../components/ui/DataTable';
import TableActions from '../components/ui/TableActions';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import ModalDialog from '../components/ui/ModalDialog';
import useClientPagination from '../hooks/useClientPagination';
import { getCallableErrorMessage } from '../utils/planUtils';
import {
  formatRepRange,
  validateRepRange,
  validateWeightRange,
  cleanInstructionSteps,
  validateInstructionSteps,
  normalizeSecondaryMuscles,
  resolveInjuryRiskLabel,
} from '../utils/exerciseUtils';

const emptyForm = {
  name: '',
  difficulty: 'Beginner',
  equipment: '',
  muscle: '',
  muscleGroup: '',
  secondaryMuscles: [],
  injuryRisk: [],
  instructionSteps: [''],
  minReps: '',
  maxReps: '',
  minKg: '',
  maxKg: '',
  gifUrl: '',
};

const difficultyTone = (difficulty) =>
  difficulty === 'Advanced' ? 'danger' : difficulty === 'Intermediate' ? 'warning' : 'success';

const DELETE_CONFIRMATION = 'DELETE';

const normalizeExerciseName = (value) => (value || '').trim().toLowerCase();

const exportValue = (value) => {
  if (value === undefined || value === null || value === '') return '—';
  return value;
};

function ExercisesStyles() {
  return (
    <style>{`
      .wwex-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwex-success {
        margin-top: calc(var(--ww-space-5) * -1);
      }
      .wwex-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwex-form-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwex-table .wwa-table th:last-child,
      .wwex-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwex-name-cell {
        min-width: 0;
      }
      .wwex-name-cell__title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwex-name-cell__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 3px;
      }
      .wwex-target-cell {
        min-width: 0;
      }
      .wwex-target-cell__primary {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwex-target-cell__secondary {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 3px;
      }
      .wwex-injury-summary {
        color: var(--ww-text-sec);
      }
      .wwex-inline-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        flex-wrap: nowrap;
        white-space: nowrap;
      }
      .wwex-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwex-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
      }
      .wwex-risk-empty {
        padding: 14px 0;
      }
      .wwex-modal-copy {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwex-modal-note {
        margin-top: 10px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwex-media-note {
        padding: 12px 14px;
        border-radius: 12px;
        border: 1px solid var(--ww-divider);
        background: var(--ww-elevated);
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwa-modal {
        position: fixed;
        inset: 0;
        z-index: 1200;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: rgba(15, 23, 42, 0.58);
        backdrop-filter: blur(2px);
      }
      .wwa-modal__panel {
        width: min(100%, 560px);
        max-height: calc(100vh - 48px);
        overflow: auto;
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: 20px;
        box-shadow: var(--ww-shadow-lg);
      }
      .wwa-modal__header,
      .wwa-modal__footer {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
        padding: 18px 20px;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwa-modal__footer {
        align-items: center;
        justify-content: flex-end;
        border-top: 1px solid var(--ww-divider);
        border-bottom: 0;
        flex-wrap: wrap;
      }
      .wwa-modal__header-main {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .wwa-modal__title {
        margin: 0;
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-primary-dark);
      }
      .wwa-modal__description {
        margin: 0;
        font-size: var(--ww-type-body-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwa-modal__body {
        padding: 20px;
      }
      @media (max-width: 1100px) {
        .wwex-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      @media (max-width: 720px) {
        .wwa-modal {
          padding: 12px;
        }
      }
    `}</style>
  );
}

function Exercises() {
  const [exercises, setExercises] = useState([]);
  const [injuryCategories, setInjuryCategories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [search, setSearch] = useState('');
  const [difficultyFilter, setDifficultyFilter] = useState('all');
  const [muscleFilter, setMuscleFilter] = useState('all');
  const [equipmentFilter, setEquipmentFilter] = useState('all');
  const [muscleGroupFilter, setMuscleGroupFilter] = useState('all');

  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(emptyForm);
  const [formError, setFormError] = useState('');
  const [saving, setSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');

  const [selectedExerciseId, setSelectedExerciseId] = useState(null);
  const [deleteExerciseId, setDeleteExerciseId] = useState(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [deleteError, setDeleteError] = useState('');

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      setLoadError('');

      try {
        const [exercisesSnap, injurySnap] = await Promise.all([
          getDocs(collection(db, 'exercises')),
          getDocs(collection(db, 'injuryCategories')),
        ]);

        setExercises(exercisesSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() })));
        setInjuryCategories(injurySnap.docs.map((doc) => ({ id: doc.id, ...doc.data() })));
      } catch (err) {
        console.error(err);
        setLoadError('Failed to load exercises. Please try again.');
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

  const toggleInjuryRisk = (categoryName) => {
    setForm((prev) => {
      const lower = categoryName.toLowerCase();
      const already = prev.injuryRisk.some((value) => (value || '').toLowerCase() === lower);
      const withoutVariants = prev.injuryRisk.filter((value) => (value || '').toLowerCase() !== lower);
      return {
        ...prev,
        injuryRisk: already ? withoutVariants : [...withoutVariants, categoryName],
      };
    });
  };

  const closeForm = () => {
    setShowForm(false);
    setEditingId(null);
    setFormError('');
  };

  const closeDeleteDialog = () => {
    if (saving) return;
    setDeleteExerciseId(null);
    setDeleteConfirmation('');
    setDeleteError('');
  };

  const openExerciseView = (exercise) => {
    setSelectedExerciseId(exercise.id);
    setFormError('');
    setDeleteError('');
  };

  const openExerciseDelete = (exercise) => {
    setDeleteExerciseId(exercise.id);
    setDeleteConfirmation('');
    setFormError('');
    setDeleteError('');
  };

  const openAddForm = () => {
    setShowForm(true);
    setEditingId(null);
    setForm(emptyForm);
    setFormError('');
    setDeleteError('');
    setSelectedExerciseId(null);
  };

  const handleAdd = async () => {
    if (!form.name.trim()) {
      setFormError('Exercise Name is required.');
      return;
    }
    if (!form.muscle.trim()) {
      setFormError('Primary muscle is required.');
      return;
    }

    const duplicateExists = exercises.some(
      (exercise) =>
        exercise.id !== editingId &&
        normalizeExerciseName(exercise.name) === normalizeExerciseName(form.name)
    );
    if (duplicateExists) {
      setFormError('An exercise with this name already exists.');
      return;
    }

    const stepsError = validateInstructionSteps(form.instructionSteps);
    if (stepsError) {
      setFormError(stepsError);
      return;
    }

    const minReps = Number(form.minReps);
    const maxReps = Number(form.maxReps);
    const repsError = validateRepRange(minReps, maxReps);
    if (repsError) {
      setFormError(repsError);
      return;
    }

    const minKg = Number(form.minKg);
    const maxKg = Number(form.maxKg);
    const weightError = validateWeightRange(minKg, maxKg);
    if (weightError) {
      setFormError(weightError);
      return;
    }

    const payload = {
      name: form.name.trim(),
      difficulty: form.difficulty,
      equipment: form.equipment.trim(),
      muscle: form.muscle.trim(),
      muscleGroup: form.muscleGroup.trim(),
      secondaryMuscles: normalizeSecondaryMuscles(form.secondaryMuscles, form.muscle),
      injuryRisk: form.injuryRisk,
      instructionSteps: cleanInstructionSteps(form.instructionSteps),
      minReps,
      maxReps,
      minKg,
      maxKg,
      gifUrl: form.gifUrl.trim() || null,
    };

    setSaving(true);
    setFormError('');

    try {
      const wasEditing = Boolean(editingId);

      if (wasEditing) {
        const adminUpdateExercise = httpsCallable(functions, 'adminUpdateExercise');

        const result = await adminUpdateExercise({
          exerciseId: editingId,
          exercise: payload,
        });

        const savedExercise = result.data.exercise || payload;

        setExercises((prev) =>
          prev.map((exercise) =>
            exercise.id === editingId
              ? { ...exercise, ...savedExercise }
              : exercise
          )
        );

        setSelectedExerciseId((prev) => (prev === editingId ? editingId : prev));
        setEditingId(null);
      } else {
        const adminCreateExercise = httpsCallable(functions, 'adminCreateExercise');

        const result = await adminCreateExercise({
          exercise: payload,
        });

        setExercises((prev) => [
          ...prev,
          {
            id: result.data.exerciseId,
            ...(result.data.exercise || payload),
          },
        ]);
      }

      setForm(emptyForm);
      setShowForm(false);
      setSuccessMsg(wasEditing ? 'Exercise updated successfully' : 'Exercise added successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setFormError(getCallableErrorMessage(err, 'Failed to save exercise. Please try again.'));
    }

    setSaving(false);
  };

  const handleEdit = (exercise) => {
    setForm({
      name: exercise.name || '',
      difficulty: exercise.difficulty || 'Beginner',
      equipment: exercise.equipment || '',
      muscle: exercise.muscle || '',
      muscleGroup: exercise.muscleGroup || '',
      secondaryMuscles: Array.isArray(exercise.secondaryMuscles) ? [...exercise.secondaryMuscles] : [],
      injuryRisk: Array.isArray(exercise.injuryRisk) ? exercise.injuryRisk : [],
      instructionSteps:
        Array.isArray(exercise.instructionSteps) && exercise.instructionSteps.length > 0
          ? [...exercise.instructionSteps]
          : [''],
      minReps: exercise.minReps ?? '',
      maxReps: exercise.maxReps ?? '',
      minKg: exercise.minKg ?? '',
      maxKg: exercise.maxKg ?? '',
      gifUrl: exercise.gifUrl || '',
    });
    setEditingId(exercise.id);
    setFormError('');
    setDeleteError('');
    setShowForm(true);
    setSelectedExerciseId(exercise.id);
  };

  const handleDelete = async () => {
    const exercise = exercises.find((item) => item.id === deleteExerciseId);
    if (!exercise) return;
    setSaving(true);
    setDeleteError('');
    try {
      const adminDeleteExercise = httpsCallable(functions, 'adminDeleteExercise');

      await adminDeleteExercise({
        exerciseId: exercise.id,
      });

      setExercises((prev) => prev.filter((existing) => existing.id !== exercise.id));
      setSelectedExerciseId((prev) => (prev === exercise.id ? null : prev));
      if (editingId === exercise.id) {
        closeForm();
        setForm(emptyForm);
      }
      closeDeleteDialog();
      setSuccessMsg(`"${exercise.name || 'Exercise'}" was deleted successfully.`);
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setDeleteError(getCallableErrorMessage(err, 'Failed to delete exercise. Please try again.'));
    } finally {
      setSaving(false);
    }
  };

  const difficultyOptions = Array.from(new Set(exercises.map((exercise) => exercise.difficulty).filter(Boolean))).sort();
  const equipmentOptions = Array.from(new Set(exercises.map((exercise) => exercise.equipment).filter(Boolean))).sort();
  const muscleOptions = Array.from(new Set(exercises.map((exercise) => exercise.muscle).filter(Boolean))).sort();
  const muscleGroupOptions = Array.from(new Set(exercises.map((exercise) => exercise.muscleGroup).filter(Boolean))).sort();

  const filtered = useMemo(() => {
    return exercises.filter((exercise) => {
      const query = search.toLowerCase();
      const matchesSearch =
        (exercise.name || '').toLowerCase().includes(query) ||
        (exercise.muscle || '').toLowerCase().includes(query) ||
        (exercise.equipment || '').toLowerCase().includes(query) ||
        (exercise.muscleGroup || '').toLowerCase().includes(query);
      const matchesDifficulty = difficultyFilter === 'all' || exercise.difficulty === difficultyFilter;
      const matchesEquipment = equipmentFilter === 'all' || exercise.equipment === equipmentFilter;
      const matchesMuscle = muscleFilter === 'all' || exercise.muscle === muscleFilter;
      const matchesMuscleGroup = muscleGroupFilter === 'all' || exercise.muscleGroup === muscleGroupFilter;

      return matchesSearch && matchesDifficulty && matchesEquipment && matchesMuscle && matchesMuscleGroup;
    });
  }, [exercises, search, difficultyFilter, equipmentFilter, muscleFilter, muscleGroupFilter]);

  const exercisesPagination = useClientPagination(filtered, {
    resetKey: [search, difficultyFilter, equipmentFilter, muscleFilter, muscleGroupFilter].join('|'),
  });

  const selectedExercise = exercises.find((exercise) => exercise.id === selectedExerciseId) || null;
  const deleteExercise = exercises.find((exercise) => exercise.id === deleteExerciseId) || null;
  const editingExercise = exercises.find((exercise) => exercise.id === editingId) || null;

  const handleExport = () => {
    const rows = filtered.map((exercise) => ({
      'Exercise ID': exportValue(exercise.id),
      'Exercise Name': exportValue(exercise.name),
      Difficulty: exportValue(exercise.difficulty || 'Beginner'),
      Equipment: exportValue(exercise.equipment),
      'Primary Muscle': exportValue(exercise.muscle),
      'Muscle Group': exportValue(exercise.muscleGroup),
      'Secondary Muscles': Array.isArray(exercise.secondaryMuscles) && exercise.secondaryMuscles.length > 0 ? exercise.secondaryMuscles.join(', ') : '—',
      'Injury Risk':
        Array.isArray(exercise.injuryRisk) && exercise.injuryRisk.length > 0
          ? exercise.injuryRisk.map((risk) => resolveInjuryRiskLabel(risk, injuryCategories)).filter(Boolean).join(', ')
          : '—',
      'Minimum Reps': exercise.minReps ?? '—',
      'Maximum Reps': exercise.maxReps ?? '—',
      'Minimum Weight (kg)': exercise.minKg ?? '—',
      'Maximum Weight (kg)': exercise.maxKg ?? '—',
      Instructions:
        Array.isArray(exercise.instructionSteps) && exercise.instructionSteps.length > 0
          ? cleanInstructionSteps(exercise.instructionSteps).join(' | ')
          : '—',
      'GIF URL': exportValue(exercise.gifUrl),
      'Legacy Image URL': exportValue(exercise.imageUrl),
    }));

    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [
      { wch: 22 },
      { wch: 26 },
      { wch: 12 },
      { wch: 16 },
      { wch: 16 },
      { wch: 16 },
      { wch: 24 },
      { wch: 26 },
      { wch: 12 },
      { wch: 12 },
      { wch: 16 },
      { wch: 16 },
      { wch: 50 },
      { wch: 30 },
      { wch: 30 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Exercises');
    XLSX.writeFile(workbook, 'WiseWorkout_Exercises.xlsx');
  };

  const difficultyFilterOptions = [{ value: 'all', label: 'Difficulty: All' }, ...difficultyOptions.map((value) => ({ value, label: value }))];
  const muscleFilterOptions = [{ value: 'all', label: 'Primary Muscle: All' }, ...muscleOptions.map((value) => ({ value, label: value }))];
  const equipmentFilterOptions = [{ value: 'all', label: 'Equipment: All' }, ...equipmentOptions.map((value) => ({ value, label: value }))];
  const muscleGroupFilterOptions = [{ value: 'all', label: 'Muscle Group: All' }, ...muscleGroupOptions.map((value) => ({ value, label: value }))];

  const riskSummary = (exercise) => {
    const count = Array.isArray(exercise.injuryRisk) ? exercise.injuryRisk.filter(Boolean).length : 0;
    if (count === 0) return 'No listed risks';
    if (count === 1) return '1 risk';
    return `${count} risks`;
  };

  const columns = [
    {
      key: 'exercise',
      header: 'Exercise',
      render: (exercise) => (
        <div className="wwex-name-cell">
          <div className="wwex-name-cell__title">{exercise.name || '—'}</div>
          {exercise.equipment ? <div className="wwex-name-cell__meta">{exercise.equipment}</div> : null}
        </div>
      ),
    },
    {
      key: 'muscle',
      header: 'Primary Muscle',
      render: (exercise) => exercise.muscle || '—',
    },
    {
      key: 'muscleGroup',
      header: 'Muscle Group',
      render: (exercise) => exercise.muscleGroup || '—',
    },
    {
      key: 'difficulty',
      header: 'Difficulty',
      render: (exercise) => <Badge tone={difficultyTone(exercise.difficulty)}>{exercise.difficulty || 'Beginner'}</Badge>,
    },
    {
      key: 'injuryRisk',
      header: 'Injury Risk',
      render: (exercise) => <span className="wwex-injury-summary">{riskSummary(exercise)}</span>,
    },
    {
      key: 'repRange',
      header: 'Rep Range',
      render: (exercise) => formatRepRange(exercise.minReps, exercise.maxReps),
    },
    {
      key: 'weightRange',
      header: 'Weight Range',
      render: (exercise) => `${exercise.minKg ?? '—'}–${exercise.maxKg ?? '—'} kg`,
    },
  ];

  return (
    <div className="wwex-page">
      <AdminStyles />
      <ExercisesStyles />

      <PageHeader
        title="Exercises"
        description={loading ? 'Loading exercises…' : `${exercises.length} exercises in library`}
        actions={
          !loading ? (
            <>
              {successMsg ? (
                <span className="wwa-status-pill">
                  <span className="wwa-status-dot" />
                  {successMsg}
                </span>
              ) : null}
              <button className="wwa-btn wwa-btn-secondary" onClick={handleExport} disabled={filtered.length === 0}>
                <Download aria-hidden="true" size={16} strokeWidth={2} />
                Export to Excel
              </button>
              <button className="wwa-btn wwa-btn-primary" onClick={openAddForm}>
                <Plus aria-hidden="true" size={16} strokeWidth={2} />
                Add Exercise
              </button>
            </>
          ) : null
        }
      />

      {loadError ? <ErrorState title="Failed to load exercises" message={loadError} /> : null}

      {showForm ? (
        <div className="wwa-panel wwex-form">
          <div>
            <div className="wwa-panel-title">{editingId ? 'Edit Exercise' : 'Add Exercise'}</div>
            <div className="wwa-panel-subtitle">Update the exercise details while preserving the existing exercise schema and validation rules.</div>
          </div>

          {formError ? <div className="wwa-alert-error">{formError}</div> : null}

          <FormSection title="Basic Information" description="Core exercise identity and media.">
            <FormField label="Exercise Name" labelFor="exercise-name" required>
              <input
                id="exercise-name"
                className="wwa-input"
                value={form.name}
                onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
                placeholder="e.g. Squat"
              />
            </FormField>

            <SelectField
              id="exercise-difficulty"
              label="Difficulty"
              value={form.difficulty}
              onChange={(event) => setForm((prev) => ({ ...prev, difficulty: event.target.value }))}
              options={[
                { value: 'Beginner', label: 'Beginner' },
                { value: 'Intermediate', label: 'Intermediate' },
                { value: 'Advanced', label: 'Advanced' },
              ]}
            />

            <FormField label="Equipment" labelFor="exercise-equipment">
              <input
                id="exercise-equipment"
                className="wwa-input"
                value={form.equipment}
                onChange={(event) => setForm((prev) => ({ ...prev, equipment: event.target.value }))}
                placeholder="e.g. Barbell"
              />
            </FormField>

            <FormField label="GIF URL" labelFor="exercise-gif">
              <input
                id="exercise-gif"
                className="wwa-input"
                value={form.gifUrl}
                onChange={(event) => setForm((prev) => ({ ...prev, gifUrl: event.target.value }))}
                placeholder="https://…"
              />
            </FormField>

            {editingExercise?.imageUrl ? (
              <FormField
                label="Legacy Image URL"
                labelFor="exercise-image-url"
                fullWidth
                helpText="This legacy mobile fallback media is preserved automatically. GIF URL remains the admin-controlled media field."
              >
                <input id="exercise-image-url" className="wwa-input" value={editingExercise.imageUrl} readOnly />
              </FormField>
            ) : null}
          </FormSection>

          <FormSection title="Classification" description="Primary and secondary muscle targeting.">
            <FormField label="Primary Muscle" labelFor="exercise-muscle" required helpText="The main muscle targeted by this exercise.">
              <input
                id="exercise-muscle"
                className="wwa-input"
                value={form.muscle}
                onChange={(event) => setForm((prev) => ({ ...prev, muscle: event.target.value }))}
                placeholder="e.g. Legs"
              />
            </FormField>

            <FormField
              label="Muscle Group"
              labelFor="exercise-muscle-group"
              helpText="Used to classify exercises and support injury-based filtering."
            >
              <input
                id="exercise-muscle-group"
                className="wwa-input"
                value={form.muscleGroup}
                onChange={(event) => setForm((prev) => ({ ...prev, muscleGroup: event.target.value }))}
                placeholder="e.g. Thighs"
              />
            </FormField>

            <FormField
              label="Secondary Muscles"
              labelFor="exercise-secondary-muscles"
              fullWidth
              helpText="Add supporting muscle targets without changing the stored tag format."
            >
              <TagListEditor
                tags={form.secondaryMuscles}
                onChange={(next) => setForm((prev) => ({ ...prev, secondaryMuscles: next }))}
                disabled={saving}
                placeholder="e.g. Glutes"
              />
            </FormField>
          </FormSection>

          <FormSection title="Training Limits" description="Allowed rep and weight ranges recorded by users.">
            <FormField label="Minimum Reps" labelFor="exercise-min-reps">
              <input
                id="exercise-min-reps"
                type="number"
                min="1"
                step="1"
                className="wwa-input"
                value={form.minReps}
                onChange={(event) => setForm((prev) => ({ ...prev, minReps: event.target.value }))}
              />
            </FormField>

            <FormField label="Maximum Reps" labelFor="exercise-max-reps">
              <input
                id="exercise-max-reps"
                type="number"
                min="1"
                step="1"
                className="wwa-input"
                value={form.maxReps}
                onChange={(event) => setForm((prev) => ({ ...prev, maxReps: event.target.value }))}
              />
            </FormField>

            <FormField
              label="Minimum Weight (kg)"
              labelFor="exercise-min-kg"
              helpText="Restricts the minimum weight users can record."
            >
              <input
                id="exercise-min-kg"
                type="number"
                min="0"
                step="any"
                className="wwa-input"
                value={form.minKg}
                onChange={(event) => setForm((prev) => ({ ...prev, minKg: event.target.value }))}
              />
            </FormField>

            <FormField
              label="Maximum Weight (kg)"
              labelFor="exercise-max-kg"
              helpText="Restricts the maximum weight users can record."
            >
              <input
                id="exercise-max-kg"
                type="number"
                min="0"
                step="any"
                className="wwa-input"
                value={form.maxKg}
                onChange={(event) => setForm((prev) => ({ ...prev, maxKg: event.target.value }))}
              />
            </FormField>
          </FormSection>

          <FormSection title="Injury Considerations" description="Existing injury-risk values preserved exactly as stored." columns={1}>
            <FormField label="Injury Risks" labelFor="exercise-injury-risks" fullWidth>
              {injuryCategories.length === 0 ? (
                <div className="wwa-help-text wwex-risk-empty">No injury categories yet — add some in the Injuries tab.</div>
              ) : (
                <div id="exercise-injury-risks" className="wwa-check-grid">
                  {injuryCategories.map((category) => {
                    const checked = form.injuryRisk.some(
                      (value) => (value || '').toLowerCase() === (category.name || '').toLowerCase()
                    );

                    return (
                      <label
                        key={category.id}
                        className={`wwa-check-item ${checked ? 'wwa-check-item--checked' : ''}`}
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() => toggleInjuryRisk(category.name)}
                        />
                        <span>{category.name}</span>
                      </label>
                    );
                  })}
                </div>
              )}
            </FormField>
          </FormSection>

          <FormSection title="Instructions" description="Ordered step-by-step guidance shown to users." columns={1}>
            <InstructionStepsEditor
              steps={form.instructionSteps}
              onChange={(next) => setForm((prev) => ({ ...prev, instructionSteps: next }))}
              disabled={saving}
            />
          </FormSection>

          <div className="wwex-form-actions">
            <button className="wwa-btn wwa-btn-secondary" onClick={closeForm} disabled={saving}>
              Cancel
            </button>
            <button className="wwa-btn wwa-btn-primary" onClick={handleAdd} disabled={saving}>
              {saving ? 'Saving...' : 'Save Exercise'}
            </button>
          </div>
        </div>
      ) : null}

      {loading ? (
        <LoadingState rows={6} />
      ) : (
        <div className={`wwex-layout ${selectedExercise ? 'has-detail' : ''}`}>
          <div>
            <FilterBar
              search={
                <SearchInput
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  onClear={() => setSearch('')}
                  placeholder="Search exercises…"
                  label="Search exercises"
                />
              }
              filters={
                <>
                  <SelectField
                    value={difficultyFilter}
                    onChange={(event) => setDifficultyFilter(event.target.value)}
                    options={difficultyFilterOptions}
                    aria-label="Filter by difficulty"
                  />
                  <SelectField
                    value={equipmentFilter}
                    onChange={(event) => setEquipmentFilter(event.target.value)}
                    options={equipmentFilterOptions}
                    aria-label="Filter by equipment"
                  />
                  <SelectField
                    value={muscleFilter}
                    onChange={(event) => setMuscleFilter(event.target.value)}
                    options={muscleFilterOptions}
                    aria-label="Filter by primary muscle"
                  />
                  <SelectField
                    value={muscleGroupFilter}
                    onChange={(event) => setMuscleGroupFilter(event.target.value)}
                    options={muscleGroupFilterOptions}
                    aria-label="Filter by muscle group"
                  />
                </>
              }
              count={`${filtered.length} of ${exercises.length} exercises`}
            />

            <DataTable
              className="wwex-table"
              columns={columns}
              rows={exercisesPagination.paginatedItems}
              selectedRowKey={selectedExerciseId}
              getRowKey={(exercise) => exercise.id}
              onRowClick={(exercise) => openExerciseView(exercise)}
              minWidth={1040}
              pagination={{
                currentPage: exercisesPagination.currentPage,
                pageSize: exercisesPagination.pageSize,
                totalItems: exercisesPagination.totalItems,
                totalPages: exercisesPagination.totalPages,
                pageSizeOptions: exercisesPagination.pageSizeOptions,
                onPageChange: exercisesPagination.setCurrentPage,
                onPageSizeChange: exercisesPagination.setPageSize,
              }}
              emptyIcon={null}
              emptyTitle="No exercises found"
              emptyMessage={search ? 'Try a different search term or clear one of the filters.' : 'No exercises in the library yet.'}
              renderRowActions={(exercise) => (
                <div className="wwex-inline-actions">
                  <button
                    type="button"
                    className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                    onClick={(event) => {
                      event.stopPropagation();
                      openExerciseView(exercise);
                    }}
                    aria-label={`View ${exercise.name || 'exercise'}`}
                  >
                    <Eye aria-hidden="true" size={14} strokeWidth={2} />
                    View
                  </button>
                  <TableActions
                    label={`Actions for ${exercise.name || 'exercise'}`}
                    items={[
                      {
                        key: 'edit',
                        label: 'Edit',
                        icon: <Pencil aria-hidden="true" size={14} strokeWidth={2} />,
                        onSelect: () => handleEdit(exercise),
                      },
                      { type: 'divider' },
                      {
                        key: 'delete',
                        label: 'Delete',
                        tone: 'danger',
                        icon: <Trash2 aria-hidden="true" size={14} strokeWidth={2} />,
                        onSelect: () => openExerciseDelete(exercise),
                      },
                    ]}
                  />
                </div>
              )}
            />
          </div>

          {selectedExercise ? (
            <ExerciseDetailPanel
              exercise={selectedExercise}
              injuryCategories={injuryCategories}
              onClose={() => setSelectedExerciseId(null)}
              onEdit={handleEdit}
              onDelete={openExerciseDelete}
            />
          ) : null}
        </div>
      )}

      <ModalDialog
        open={Boolean(deleteExercise)}
        title="Delete Exercise"
        description="This permanently deletes the exercise from the exercise catalog. Existing plans keep their embedded exercise data, but the exercise will no longer be available for new plan selection."
        onClose={closeDeleteDialog}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeDeleteDialog} disabled={saving}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={handleDelete}
              disabled={saving || deleteConfirmation !== DELETE_CONFIRMATION}
            >
              {saving ? 'Deleting...' : 'Delete Exercise'}
            </button>
          </>
        }
      >
        <div className="wwex-modal-copy">
          Delete <strong>"{deleteExercise?.name || 'this exercise'}"</strong>?
        </div>
        <FormSection columns={1}>
          <FormField label="Confirmation" labelFor="exercise-delete-confirmation" required fullWidth>
            <input
              id="exercise-delete-confirmation"
              type="text"
              className="wwa-input"
              value={deleteConfirmation}
              onChange={(event) => setDeleteConfirmation(event.target.value)}
              placeholder={DELETE_CONFIRMATION}
            />
          </FormField>
        </FormSection>
        {deleteError ? <div className="wwa-alert-error">{deleteError}</div> : null}
      </ModalDialog>
    </div>
  );
}

export default Exercises;
