import React from 'react';

const menuItems = [
  { id: 'dashboard', label: 'Dashboard', icon: '📊' },
  { id: 'users', label: 'Users', icon: '👥' },
  { id: 'businessPartners', label: 'Business Partners', icon: '🤝' },
  { id: 'exercises', label: 'Exercises', icon: '💪' },
  { id: 'settings', label: 'Settings', icon: '⚙️' },
  { id: 'analytics', label: 'Analytics', icon: '📈' },
  { id: 'challenges', label: 'Challenges', icon: '🏆' },
  { id: 'plans', label: 'Plans', icon: '📋' },
  { id: 'posts', label: 'Posts', icon: '📝' },
  { id: 'injuries', label: 'Injuries', icon: '🩹' },
  { id: 'broadcasts', label: 'Broadcasts', icon: '📢' },
  { id: 'badges', label: 'Badges', icon: '🏅' },
];

function Sidebar({ currentPage, setCurrentPage, onLogout }) {
  return (
    <div style={{
      width: '220px',
      minHeight: '100vh',
      backgroundColor: '#1a1a2e',
      color: 'white',
      display: 'flex',
      flexDirection: 'column',
      padding: '24px 0',
      flexShrink: 0,
    }}>
      <style>{`
        .wwa-nav-item {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 11px 24px;
          cursor: pointer;
          font-size: 14px;
          border-left: 3px solid transparent;
          color: #a0a0b0;
          transition: background 0.15s ease, color 0.15s ease;
        }
        .wwa-nav-item:hover {
          background: rgba(255, 255, 255, 0.04);
          color: #e5e5f0;
        }
        .wwa-nav-item-active, .wwa-nav-item-active:hover {
          background: #16213e;
          border-left-color: #6c63ff;
          color: #ffffff;
          font-weight: 600;
        }
        .wwa-nav-icon { font-size: 15px; width: 18px; text-align: center; }
        .wwa-logout {
          padding: 12px 24px;
          cursor: pointer;
          color: #ff6b6b;
          font-size: 14px;
          display: flex;
          align-items: center;
          gap: 12px;
          transition: background 0.15s ease;
        }
        .wwa-logout:hover { background: rgba(255, 107, 107, 0.08); }
      `}</style>

      <div style={{ padding: '0 24px 28px', borderBottom: '1px solid rgba(255,255,255,0.06)', marginBottom: '12px' }}>
        <div style={{ fontSize: '12px', color: '#8a8aa0', marginBottom: '4px', letterSpacing: '0.04em', textTransform: 'uppercase' }}>WiseWorkout</div>
        <div style={{ fontSize: '17px', fontWeight: '700', letterSpacing: '-0.01em' }}>Admin Portal</div>
      </div>

      <div style={{ flex: 1 }}>
        {menuItems.map(item => (
          <div
            key={item.id}
            onClick={() => setCurrentPage(item.id)}
            className={`wwa-nav-item ${currentPage === item.id ? 'wwa-nav-item-active' : ''}`}
          >
            <span className="wwa-nav-icon">{item.icon}</span>
            <span>{item.label}</span>
          </div>
        ))}
      </div>

      <div onClick={onLogout} className="wwa-logout">
        <span className="wwa-nav-icon">🚪</span>
        <span>Sign out</span>
      </div>
    </div>
  );
}

export default Sidebar;
