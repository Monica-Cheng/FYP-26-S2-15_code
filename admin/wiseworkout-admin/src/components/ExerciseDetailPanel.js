import React, { useEffect, useState } from 'react';
import Badge from './ui/Badge';
import DetailDrawer from './ui/DetailDrawer';
import {
  formatRepRange,
  formatWeightRange,
  formatSecondaryMuscles,
  isValidGifUrl,
  resolveInjuryRiskLabel,
} from '../utils/exerciseUtils';

const difficultyTone = (difficulty) =>
  difficulty === 'Advanced' ? 'danger' : difficulty === 'Intermediate' ? 'warning' : 'success';

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;

  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

function ExerciseDetailPanel({ exercise, injuryCategories, onClose }) {
  const [gifFailed, setGifFailed] = useState(false);
  const exerciseId = exercise ? exercise.id : null;

  useEffect(() => {
    setGifFailed(false);
  }, [exerciseId]);

  if (!exercise) return null;

  const showGif = exercise.gifUrl && isValidGifUrl(exercise.gifUrl) && !gifFailed;
  const steps = Array.isArray(exercise.instructionSteps) ? exercise.instructionSteps.filter(Boolean) : [];
  const risks = Array.isArray(exercise.injuryRisk)
    ? exercise.injuryRisk.map((risk) => resolveInjuryRiskLabel(risk, injuryCategories)).filter(Boolean)
    : [];

  return (
    <DetailDrawer
      title="Exercise"
      open={Boolean(exercise)}
      onClose={onClose}
      summary={
        <div className="wwa-detail-summary">
          <div className="wwa-detail-summary__media">
            {showGif ? (
              <img
                src={exercise.gifUrl}
                alt={exercise.name || 'Exercise'}
                onError={() => setGifFailed(true)}
              />
            ) : (
              <div className="wwa-detail-summary__placeholder">
                {exercise.gifUrl ? 'GIF could not be loaded' : 'No GIF available'}
              </div>
            )}
          </div>
          <div className="wwa-detail-summary__content">
            <div className="wwa-detail-summary__title">{exercise.name || 'Unnamed exercise'}</div>
            <div className="wwa-detail-summary__meta">
              <Badge tone={difficultyTone(exercise.difficulty)}>{exercise.difficulty || 'Beginner'}</Badge>
            </div>
          </div>
        </div>
      }
    >
      <section className="wwa-detail-section">
        <div className="wwa-detail-section__title">Overview</div>
        <DetailRow label="Equipment" value={exercise.equipment || '—'} />
        <DetailRow label="Primary Muscle" value={exercise.muscle || '—'} />
        <DetailRow label="Muscle Group" value={exercise.muscleGroup || '—'} />
        <DetailRow label="Secondary Muscles" value={formatSecondaryMuscles(exercise.secondaryMuscles)} />
      </section>

      <section className="wwa-detail-section">
        <div className="wwa-detail-section__title">Training Limits</div>
        <DetailRow label="Rep Range" value={formatRepRange(exercise.minReps, exercise.maxReps)} />
        <DetailRow label="Weight Range" value={formatWeightRange(exercise.minKg, exercise.maxKg)} />
      </section>

      <section className="wwa-detail-section">
        <div className="wwa-detail-section__title">Injury Considerations</div>
        {risks.length > 0 ? (
          risks.length <= 4 ? (
            <div className="wwa-chip-list">
              {risks.map((risk) => (
                <Badge key={risk} tone="warning">
                  {risk}
                </Badge>
              ))}
            </div>
          ) : (
            <ul className="wwa-detail-list">
              {risks.map((risk) => (
                <li key={risk}>{risk}</li>
              ))}
            </ul>
          )
        ) : (
          <div className="wwa-help-text">No listed risks</div>
        )}
      </section>

      <section className="wwa-detail-section">
        <div className="wwa-detail-section__title">Instructions</div>
        {steps.length > 0 ? (
          <ol className="wwa-detail-list">
            {steps.map((step, index) => (
              <li key={`${exercise.id}-step-${index}`}>{step}</li>
            ))}
          </ol>
        ) : (
          <div className="wwa-help-text">No instructions added yet.</div>
        )}
      </section>
    </DetailDrawer>
  );
}

export default ExerciseDetailPanel;
