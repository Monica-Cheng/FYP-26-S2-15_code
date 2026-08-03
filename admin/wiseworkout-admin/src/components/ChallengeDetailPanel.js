import React, { useState } from 'react';
import { formatDate } from '../utils/dateUtils';
import { resolveCategoryDisplay, formatGoal, computeChallengeStatus, computeInviteEligibility } from '../utils/challengeUtils';

const monoStyle = { fontFamily: 'Consolas, Menlo, monospace', fontSize: '12px' };

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

// View + Delete only — Edit Challenge hasn't been built yet (not requested
// so far). The Invite All send action stays disabled: not a permissions
// issue (the admin UID override covers this write), but because no
// challenge-invite notification shape exists anywhere in the Flutter app to
// copy — see chat. The eligibility preview below only ever reads data.
function ChallengeDetailPanel({ challenge, categories, users, onClose, onDelete }) {
  const [showInvitePreview, setShowInvitePreview] = useState(false);

  if (!challenge) return null;

  const categoryDisplay = resolveCategoryDisplay(challenge.categoryId, categories);
  const isGlobal = challenge.isGlobal === true;
  const status = computeChallengeStatus(challenge.startDate, challenge.endDate);
  const eligibility = computeInviteEligibility(challenge, users || []);

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>Challenge Detail</div>
        <button className="wwa-panel-close" onClick={onClose} aria-label="Close challenge detail">✕</button>
      </div>

      <div style={{ marginBottom: 8 }}>
        <DetailRow label="Challenge ID" value={<span style={monoStyle}>{challenge.id}</span>} />
        <DetailRow label="Name" value={challenge.name || challenge.title || '—'} />
        <DetailRow
          label="Category"
          value={categoryDisplay.missing
            ? <span style={{ color: '#cc8800' }}>⚠ {categoryDisplay.text} (category not found)</span>
            : categoryDisplay.text}
        />
        <DetailRow
          label="Category ID"
          value={challenge.categoryId ? <span style={monoStyle}>{challenge.categoryId}</span> : undefined}
        />
        <DetailRow label="Metric Type" value={challenge.metricType || '—'} />
        <DetailRow label="Unit" value={challenge.unit || '—'} />
        <DetailRow label="Goal Value" value={formatGoal(challenge, categories)} />
        <DetailRow label="Start Date" value={formatDate(challenge.startDate)} />
        <DetailRow label="End Date" value={formatDate(challenge.endDate)} />
        <DetailRow label="Type" value={isGlobal ? 'Global' : 'Private'} />
        <DetailRow label="Status" value={status} />
        <DetailRow label="Created By" value={challenge.createdBy || 'system'} />
        <DetailRow label="Participants" value={Array.isArray(challenge.participantUids) ? challenge.participantUids.length : 0} />
        <DetailRow label="Invited" value={Array.isArray(challenge.invitedUids) ? challenge.invitedUids.length : 0} />
        <DetailRow label="Created At" value={formatDate(challenge.createdAt)} />
      </div>

      {isGlobal && (
        <div style={{ marginBottom: 20 }}>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 8 }}>Invite All Users</div>

          {status === 'Ended' ? (
            <div className="wwa-alert-error">This challenge has already ended.</div>
          ) : !showInvitePreview ? (
            <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={() => setShowInvitePreview(true)}>
              Invite All Users
            </button>
          ) : (
            <div style={{ background: '#f9fafb', border: '1px solid #eef0f4', borderRadius: 12, padding: 16 }}>
              <div style={{ fontSize: 14, fontWeight: 600, color: '#111827', marginBottom: 10 }}>
                Invite all eligible WiseWorkout users to join this global challenge?
              </div>
              <DetailRow label="Challenge" value={challenge.name || challenge.title || '—'} />
              <DetailRow label="Eligible Users" value={eligibility.eligibleCount} />
              <DetailRow label="Already Participating" value={eligibility.participatingCount} />
              <DetailRow label="Already Invited" value={eligibility.invitedCount} />
              <DetailRow label="Skipped (Suspended)" value={eligibility.suspendedCount} />
              <DetailRow label="New Invitations" value={eligibility.eligibleCount} />

              <div className="wwa-alert-error" style={{ marginTop: 12 }}>
                Sending is disabled for now — the admin-only Firestore rule for this write, and the exact
                challenge-invite notification shape expected under users/{'{uid}'}/notifications, haven't
                been confirmed yet. See chat for details.
              </div>

              <div className="wwa-cell-actions" style={{ marginTop: 12 }}>
                <button className="wwa-btn wwa-btn-secondary" onClick={() => setShowInvitePreview(false)}>
                  Cancel
                </button>
                <button className="wwa-btn wwa-btn-primary" disabled>
                  Send Invitations
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      <div className="wwa-cell-actions" style={{ marginTop: 8 }}>
        <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => onDelete(challenge)}>
          Delete
        </button>
      </div>
    </div>
  );
}

export default ChallengeDetailPanel;
