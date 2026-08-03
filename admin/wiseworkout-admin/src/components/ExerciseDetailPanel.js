import React, { useState, useEffect } from 'react';
import Badge from './ui/Badge';
import {
  formatInjuryRisk, formatSecondaryMuscles, isValidGifUrl,
} from '../utils/exerciseUtils';

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

const difficultyTone = (difficulty) =>
  difficulty === 'Advanced' ? 'danger' : difficulty === 'Intermediate' ? 'warning' : 'success';

// Read-only — editing still happens through the existing Add/Edit form on
// the Exercises page, this panel is purely the "View" action.
function ExerciseDetailPanel({ exercise, injuryCategories, onClose }) {
  const [gifFailed, setGifFailed] = useState(false);
  const exerciseId = exercise ? exercise.id : null;

  useEffect(() => {
    setGifFailed(false);
  }, [exerciseId]);

  if (!exercise) return null;

  const showGif = exercise.gifUrl && isValidGifUrl(exercise.gifUrl) && !gifFailed;
  const steps = Array.isArray(exercise.instructionSteps) ? exercise.instructionSteps : [];

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>Exercise Detail</div>
        <button className="wwa-panel-close" onClick={onClose} aria-label="Close exercise detail">✕</button>
      </div>

      {showGif ? (
        <img
          src={exercise.gifUrl}
          alt={exercise.name || 'Exercise'}
          onError={() => setGifFailed(true)}
          style={{ width: '100%', maxHeight: 220, objectFit: 'contain', borderRadius: 12, marginBottom: 16, background: '#f3f4f6' }}
        />
      ) : (
        <div style={{
          width: '100%', height: 140, borderRadius: 12, marginBottom: 16,
          background: '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#9ca3af', fontSize: 13,
        }}>
          {exercise.gifUrl ? 'GIF could not be loaded' : 'No GIF available'}
        </div>
      )}

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 20, flexWrap: 'wrap' }}>
        <div style={{ fontSize: '16px', fontWeight: 700, color: '#111827' }}>{exercise.name || 'Unnamed exercise'}</div>
        <Badge tone={difficultyTone(exercise.difficulty)}>{exercise.difficulty || 'Beginner'}</Badge>
      </div>

      <div style={{ marginBottom: 20 }}>
        <DetailRow label="Equipment" value={exercise.equipment || '—'} />
        <DetailRow label="Primary Muscle" value={exercise.muscle || '—'} />
        <DetailRow label="Muscle Group" value={exercise.muscleGroup || '—'} />
        <DetailRow label="Secondary Muscles" value={formatSecondaryMuscles(exercise.secondaryMuscles)} />
        <DetailRow label="Injury Risks" value={formatInjuryRisk(exercise.injuryRisk, injuryCategories)} />
        <DetailRow label="Minimum Reps" value={exercise.minReps ?? '—'} />
        <DetailRow label="Maximum Reps" value={exercise.maxReps ?? '—'} />
        <DetailRow label="Minimum Weight" value={exercise.minKg !== undefined && exercise.minKg !== null ? `${exercise.minKg} kg` : '—'} />
        <DetailRow label="Maximum Weight" value={exercise.maxKg !== undefined && exercise.maxKg !== null ? `${exercise.maxKg} kg` : '—'} />
      </div>

      <div>
        <div className="wwa-panel-subtitle" style={{ marginBottom: 8 }}>Instructions</div>
        {steps.length > 0 ? (
          <ol style={{ margin: 0, paddingLeft: 20, display: 'flex', flexDirection: 'column', gap: 6 }}>
            {steps.map((step, i) => (
              <li key={i} style={{ fontSize: 13.5, color: '#374151', lineHeight: 1.5 }}>{step}</li>
            ))}
          </ol>
        ) : (
          <div style={{ fontSize: 13, color: '#9ca3af' }}>No instructions added yet.</div>
        )}
      </div>
    </div>
  );
}

export default ExerciseDetailPanel;
