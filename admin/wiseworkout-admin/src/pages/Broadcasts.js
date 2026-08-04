import React, { useState, useEffect, useCallback } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import { formatDate } from '../utils/dateUtils';
import { broadcastAudienceLabel, broadcastStatusLabel } from '../utils/broadcastUtils';

const MAX_MESSAGE_LENGTH = 500;

function Broadcasts() {
  const [message, setMessage] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  const [broadcasts, setBroadcasts] = useState([]);
  const [loadingHistory, setLoadingHistory] = useState(true);
  const [recipientCount, setRecipientCount] = useState(0);

  const fetchHistory = useCallback(async () => {
    setLoadingHistory(true);
  
    try {
      const adminListBroadcastDashboard = httpsCallable(
        functions,
        'adminListBroadcastDashboard'
      );
  
      const result = await adminListBroadcastDashboard();
      const data = result.data || {};
  
      setBroadcasts(
        Array.isArray(data.broadcasts) ? data.broadcasts : []
      );
  
      setRecipientCount(
        Number.isInteger(data.recipientCount)
          ? data.recipientCount
          : 0
      );
    } catch (err) {
      console.error('Failed to load broadcast dashboard:', err);
  
      const detail = err?.code ? ` (${err.code})` : '';
  
      setError(
        `Failed to load broadcast history.${detail}`
      );
    } finally {
      setLoadingHistory(false);
    }
  }, []);

  useEffect(() => {
    fetchHistory();
  }, [fetchHistory]);

  const handleSendClick = () => {
    if (!message.trim()) return;
    setError('');
    setSuccessMsg('');
    setConfirming(true);
  };

  const handleConfirmSend = async () => {
    const confirmation = window.prompt(
      `This will send the notification to ${recipientCount} users.\n\n` +
      'Type SEND TO ALL USERS exactly to continue:'
    );
  
    if (confirmation !== 'SEND TO ALL USERS') {
      setConfirming(false);
      return;
    }
  
    setSending(true);
    setError('');
  
    try {
      const adminCreateBroadcast = httpsCallable(
        functions,
        'adminCreateBroadcast'
      );
  
      const result = await adminCreateBroadcast({
        message: message.trim(),
        confirmation,
      });
  
      const sentCount = result.data?.recipientCount ?? recipientCount;
  
      setMessage('');
      setConfirming(false);
      setSuccessMsg(
        `Broadcast queued successfully for ${sentCount} users.`
      );
  
      await fetchHistory();
    } catch (err) {
      console.error('Failed to send broadcast:', err);
  
      setConfirming(false);
  
      const detail = err?.code ? ` (${err.code})` : '';
  
      setError(
        `Failed to send broadcast. Please try again.${detail}`
      );
    } finally {
      setSending(false);
    }
  };

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Broadcast Notifications"
        subtitle={loadingHistory ? 'Loading broadcast history…' : `${broadcasts.length} broadcasts sent`}
      />

      <div className="wwa-panel">
        <div className="wwa-panel-title">New Broadcast</div>
        <div className="wwa-panel-subtitle">Send a notification to WiseWorkout users</div>

        {error && (
          <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{error}</div>
        )}
        {successMsg && (
          <div style={{ marginBottom: 16 }}>
            <span className="wwa-status-pill">
              <span className="wwa-status-dot" />
              {successMsg}
            </span>
          </div>
        )}

        <div style={{ marginBottom: 16 }}>
          <label className="wwa-field-label">Notification Message</label>
          <textarea
            className="wwa-input"
            rows={4}
            required
            maxLength={MAX_MESSAGE_LENGTH}
            value={message}
            onChange={e => setMessage(e.target.value)}
            placeholder="Type the message to send to users…"
            style={{ resize: 'vertical', fontFamily: 'inherit' }}
            disabled={sending}
          />
          <div style={{ textAlign: 'right', fontSize: 12, color: '#9ca3af', marginTop: 4 }}>
            {message.length}/{MAX_MESSAGE_LENGTH}
          </div>
        </div>

        <div style={{ marginBottom: 20 }}>
          <label className="wwa-field-label">Audience</label>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <Badge tone="brand">
            All Users ({recipientCount})
          </Badge>
          <span style={{ fontSize: 12.5, color: '#9ca3af' }}>
            This broadcast will be delivered to every current WiseWorkout account.
          </span>
          </div>
        </div>

        {!confirming ? (
          <div className="wwa-cell-actions">
            <button
              className="wwa-btn wwa-btn-primary"
              onClick={handleSendClick}
              disabled={
                sending ||
                loadingHistory ||
                recipientCount <= 0 ||
                !message.trim()
              }
            >
              Send Broadcast
            </button>
          </div>
        ) : (
          <div style={{
            background: '#f9fafb',
            border: '1px solid #eef0f4',
            borderRadius: 12,
            padding: '14px 16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            flexWrap: 'wrap',
            gap: 12,
          }}>
            <span style={{ fontSize: 14, fontWeight: 600, color: '#111827' }}>
              Send this notification to all WiseWorkout users?
            </span>
            <div className="wwa-cell-actions">
              <button
                className="wwa-btn wwa-btn-secondary"
                onClick={() => setConfirming(false)}
                disabled={sending}
              >
                Cancel
              </button>
              <button
                className="wwa-btn wwa-btn-primary"
                onClick={handleConfirmSend}
                disabled={sending}
              >
                {sending ? 'Sending...' : 'Send'}
              </button>
            </div>
          </div>
        )}
      </div>

      <div className="wwa-panel-title" style={{ marginBottom: 4 }}>Broadcast History</div>
      <div className="wwa-panel-subtitle">Recent broadcasts and their delivery status</div>

      {loadingHistory ? (
        <SkeletonBlock height={220} />
      ) : (
        <div className="wwa-table-wrap">
          <table className="wwa-table">
            <thead>
              <tr>
                {['Message', 'Audience', 'Created At', 'Status'].map(h => (
                  <th key={h}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {broadcasts.map(b => (
                <tr key={b.id}>
                  <td className="wwa-cell-primary">{b.message || '—'}</td>
                  <td style={{ color: '#6b7280' }}>{broadcastAudienceLabel(b.audience)}</td>
                  <td style={{ color: '#6b7280' }}>{formatDate(b.createdAt)}</td>
                  <td>
                    <Badge tone={b.processed === true ? 'success' : 'warning'}>
                      {broadcastStatusLabel(b.processed)}
                    </Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {broadcasts.length === 0 && (
            <EmptyState
              icon="📢"
              title="No broadcasts yet"
              message="Broadcasts sent to users will appear here."
            />
          )}
        </div>
      )}
    </div>
  );
}

export default Broadcasts;
