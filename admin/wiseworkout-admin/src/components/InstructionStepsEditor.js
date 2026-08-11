import React from 'react';
import { ArrowDown, ArrowUp, Plus, Trash2 } from 'lucide-react';

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
    <div className="wwa-step-editor">
      <label className="wwa-field-label">Instruction Steps</label>
      {steps.map((step, index) => (
        <div key={index} className="wwa-step-editor__row">
          <span className="wwa-step-editor__number">
            {index + 1}.
          </span>
          <textarea
            rows={2}
            style={{ fontFamily: 'inherit' }}
            className="wwa-input wwa-step-editor__textarea"
            value={step}
            onChange={e => updateStep(index, e.target.value)}
            placeholder={`Step ${index + 1}`}
            disabled={disabled}
          />
          <div className="wwa-step-editor__controls">
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-secondary wwa-btn-icon"
              onClick={() => moveStep(index, -1)}
              disabled={disabled || index === 0}
              aria-label="Move step up"
            >
              <ArrowUp aria-hidden="true" size={14} strokeWidth={2} />
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-secondary wwa-btn-icon"
              onClick={() => moveStep(index, 1)}
              disabled={disabled || index === steps.length - 1}
              aria-label="Move step down"
            >
              <ArrowDown aria-hidden="true" size={14} strokeWidth={2} />
            </button>
          </div>
          <button
            type="button"
            className="wwa-btn wwa-btn-sm wwa-btn-danger wwa-step-editor__remove"
            onClick={() => removeStep(index)}
            disabled={disabled || steps.length <= 1}
            aria-label={`Remove step ${index + 1}`}
          >
            <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
            Remove
          </button>
        </div>
      ))}
      <div className="wwa-step-editor__footer">
        <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addStep} disabled={disabled}>
          <Plus aria-hidden="true" size={14} strokeWidth={2} />
          Add Step
        </button>
      </div>
    </div>
  );
}

export default InstructionStepsEditor;
