import React from 'react';

// Dynamic ordered-list editor for `instructionSteps` — add, edit, remove,
// and reorder (move up/down) while preserving displayed order exactly.
function InstructionStepsEditor({ steps, onChange, disabled }) {
  const updateStep = (index, value) => onChange(steps.map((s, i) => (i === index ? value : s)));
  const addStep = () => onChange([...steps, '']);
  const removeStep = (index) => onChange(steps.filter((_, i) => i !== index));

  const moveStep = (index, direction) => {
    const target = index + direction;
    if (target < 0 || target >= steps.length) return;
    const next = [...steps];
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
  };

  return (
    <div>
      <label className="wwa-field-label">Instruction Steps</label>
      {steps.map((step, index) => (
        <div key={index} style={{ display: 'flex', gap: 8, alignItems: 'flex-start', marginBottom: 8 }}>
          <span style={{ fontWeight: 700, color: '#9ca3af', minWidth: 20, paddingTop: 10, fontSize: 13 }}>
            {index + 1}.
          </span>
          <textarea
            className="wwa-input"
            rows={2}
            style={{ flex: 1, resize: 'vertical', fontFamily: 'inherit' }}
            value={step}
            onChange={e => updateStep(index, e.target.value)}
            placeholder={`Step ${index + 1}`}
            disabled={disabled}
          />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-secondary"
              onClick={() => moveStep(index, -1)}
              disabled={disabled || index === 0}
              aria-label="Move step up"
            >
              ↑
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-secondary"
              onClick={() => moveStep(index, 1)}
              disabled={disabled || index === steps.length - 1}
              aria-label="Move step down"
            >
              ↓
            </button>
          </div>
          <button
            type="button"
            className="wwa-btn wwa-btn-sm wwa-btn-danger"
            onClick={() => removeStep(index)}
            disabled={disabled || steps.length <= 1}
          >
            Remove
          </button>
        </div>
      ))}
      <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addStep} disabled={disabled}>
        + Add Step
      </button>
    </div>
  );
}

export default InstructionStepsEditor;
