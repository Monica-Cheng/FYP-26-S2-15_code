import React, { useState, useEffect } from 'react';
import Badge from './ui/Badge';
import { formatDate } from '../utils/dateUtils';

const monoStyle = { fontFamily: 'Consolas, Menlo, monospace', fontSize: '12px' };

const NUMERIC_FIELDS = [
  { key: 'calories', label: 'Calories' },
  { key: 'proteinG', label: 'Protein (g)' },
  { key: 'carbsG', label: 'Carbs (g)' },
  { key: 'fatG', label: 'Fat (g)' },
];

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

// imageBase64 may or may not already carry a data: URI prefix, and may be
// missing or corrupt — never assume it's a clean raw base64 string.
function toImageSrc(imageBase64) {
  if (!imageBase64 || typeof imageBase64 !== 'string') return null;
  if (imageBase64.startsWith('data:image')) return imageBase64;
  return `data:image/jpeg;base64,${imageBase64}`;
}

function PostDetailPanel({ post, onClose, onSave, onToggleHidden, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [imageFailed, setImageFailed] = useState(false);
  const postId = post ? post.id : null;

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    setImageFailed(false);
  }, [postId]);

  if (!post) return null;

  const isHidden = !!post.isHidden;
  const imageSrc = toImageSrc(post.imageBase64);

  const startEdit = () => {
    setForm({
      foodName: post.foodName || '',
      caption: post.caption || '',
      calories: post.calories ?? '',
      proteinG: post.proteinG ?? '',
      carbsG: post.carbsG ?? '',
      fatG: post.fatG ?? '',
    });
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  };

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    for (const field of NUMERIC_FIELDS) {
      const raw = form[field.key];
      if (raw !== '' && Number(raw) < 0) {
        setError(`${field.label} cannot be negative.`);
        return;
      }
    }

    const changes = {};
    if (form.foodName.trim() !== (post.foodName || '')) changes.foodName = form.foodName.trim();
    if (form.caption.trim() !== (post.caption || '')) changes.caption = form.caption.trim();
    NUMERIC_FIELDS.forEach(field => {
      const raw = form[field.key];
      const newValue = raw === '' ? null : Number(raw);
      const oldValue = post[field.key] ?? null;
      if (newValue !== oldValue) changes[field.key] = newValue;
    });

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');
    try {
      await onSave(post.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('Post updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setError('Failed to update post. Please try again.');
    }
    setSaving(false);
  };

  const handleToggleHidden = async () => {
    setError('');
    try {
      await onToggleHidden(post.id, isHidden);
    } catch (err) {
      console.error(err);
      setError('Failed to update post status. Please try again.');
    }
  };

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>Post Detail</div>
        <div style={{ display: 'flex', gap: 8 }}>
          {!isEditing && (
            <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={startEdit}>
              Edit
            </button>
          )}
          <button className="wwa-panel-close" onClick={onClose} aria-label="Close post detail">✕</button>
        </div>
      </div>

      {successMsg && (
        <div className="wwa-status-pill" style={{ marginBottom: 16 }}>
          <span className="wwa-status-dot" />
          {successMsg}
        </div>
      )}
      {error && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{error}</div>}

      {imageSrc && !imageFailed ? (
        <img
          src={imageSrc}
          alt="Post"
          onError={() => setImageFailed(true)}
          style={{ width: '100%', maxHeight: 220, objectFit: 'cover', borderRadius: 12, marginBottom: 16 }}
        />
      ) : (
        <div style={{
          width: '100%', height: 140, borderRadius: 12, marginBottom: 16,
          background: '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#9ca3af', fontSize: 13,
        }}>
          {post.imageBase64 ? 'Image could not be loaded' : 'No image attached'}
        </div>
      )}

      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 20, flexWrap: 'wrap' }}>
        <Badge tone="neutral">{post.type || 'Post'}</Badge>
        <Badge tone={isHidden ? 'danger' : 'success'}>{isHidden ? 'Hidden' : 'Active'}</Badge>
      </div>

      {isEditing ? (
        <div className="wwa-form-grid" style={{ marginBottom: 4 }}>
          <div>
            <label className="wwa-field-label">Food Name</label>
            <input
              className="wwa-input"
              value={form.foodName}
              onChange={e => setForm(prev => ({ ...prev, foodName: e.target.value }))}
              placeholder="Food name"
            />
          </div>
          <div className="wwa-field-full">
            <label className="wwa-field-label">Caption</label>
            <input
              className="wwa-input"
              value={form.caption}
              onChange={e => setForm(prev => ({ ...prev, caption: e.target.value }))}
              placeholder="Caption"
            />
          </div>
          {NUMERIC_FIELDS.map(field => (
            <div key={field.key}>
              <label className="wwa-field-label">{field.label}</label>
              <input
                type="number"
                min="0"
                className="wwa-input"
                value={form[field.key]}
                onChange={e => setForm(prev => ({ ...prev, [field.key]: e.target.value }))}
              />
            </div>
          ))}
        </div>
      ) : (
        <div style={{ marginBottom: 8 }}>
          <DetailRow label="Post ID" value={<span style={monoStyle}>{post.id}</span>} />
          <DetailRow label="Author" value={post.authorName || '—'} />
          <DetailRow label="Author UID" value={<span style={monoStyle}>{post.uid || '—'}</span>} />
          <DetailRow label="Food Name" value={post.foodName || '—'} />
          <DetailRow label="Caption" value={post.caption || '—'} />
          <DetailRow label="Calories" value={post.calories ?? '—'} />
          <DetailRow label="Protein" value={post.proteinG !== undefined && post.proteinG !== null ? `${post.proteinG} g` : '—'} />
          <DetailRow label="Carbs" value={post.carbsG !== undefined && post.carbsG !== null ? `${post.carbsG} g` : '—'} />
          <DetailRow label="Fat" value={post.fatG !== undefined && post.fatG !== null ? `${post.fatG} g` : '—'} />
          <DetailRow label="Reactions" value={post.reactionCount ?? 0} />
          <DetailRow label="Comments" value={post.commentCount ?? 0} />
          <DetailRow label="Created" value={formatDate(post.createdAt)} />
        </div>
      )}

      {isEditing ? (
        <div className="wwa-cell-actions" style={{ marginTop: 8 }}>
          <button className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
          <button className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
            Cancel
          </button>
        </div>
      ) : (
        <div className="wwa-cell-actions" style={{ marginTop: 8 }}>
          <button
            className={`wwa-btn wwa-btn-sm ${isHidden ? 'wwa-btn-success-soft' : 'wwa-btn-secondary'}`}
            onClick={handleToggleHidden}
          >
            {isHidden ? 'Unhide' : 'Hide'}
          </button>
          <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => onDelete(post.id)}>
            Delete
          </button>
        </div>
      )}
    </div>
  );
}

export default PostDetailPanel;
