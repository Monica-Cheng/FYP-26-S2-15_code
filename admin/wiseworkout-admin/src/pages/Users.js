import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, doc, updateDoc, deleteDoc } from 'firebase/firestore';

function Users() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const snap = await getDocs(collection(db, 'users'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setUsers(data);
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchUsers();
  }, []);

  const toggleSuspend = async (userId, currentStatus) => {
    const newStatus = currentStatus === 'suspended' ? 'active' : 'suspended';
    await updateDoc(doc(db, 'users', userId), { accountStatus: newStatus });
    setUsers(prev => prev.map(u => u.id === userId ? { ...u, accountStatus: newStatus } : u));
  };
  const handleDelete = async (userId) => {
    if (!window.confirm('Permanently delete this user? This cannot be undone.')) return;
    await deleteDoc(doc(db, 'users', userId));
    setUsers(prev => prev.filter(u => u.id !== userId));
  };

  const filtered = users.filter(u =>
    (u.displayName || '').toLowerCase().includes(search.toLowerCase()) ||
    (u.email || '').toLowerCase().includes(search.toLowerCase())
  );

  if (loading) return <div style={{ color: '#888', fontSize: '14px' }}>Loading users...</div>;

  return (
    <div>
      <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>Users</h1>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '24px' }}>{users.length} registered accounts</p>

      <input
        placeholder="Search by name or email..."
        value={search}
        onChange={e => setSearch(e.target.value)}
        style={{
          width: '100%', padding: '10px 14px', borderRadius: '8px',
          border: '1px solid #ddd', fontSize: '14px', marginBottom: '20px', outline: 'none',
        }}
      />

      <div style={{ backgroundColor: 'white', borderRadius: '12px', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '14px' }}>
          <thead>
            <tr style={{ backgroundColor: '#f8f8f8', borderBottom: '1px solid #eee' }}>
              {['Name', 'Level', 'Onboarded', 'Health Connected', 'Status', 'Action'].map(h => (
                <th key={h} style={{ padding: '14px 16px', textAlign: 'left', fontWeight: '600', color: '#555' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filtered.map(user => (
              <tr key={user.id} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{ padding: '14px 16px' }}>
                  <div style={{ fontWeight: '500' }}>{user.displayName || '—'}</div>
                  <div style={{ fontSize: '12px', color: '#aaa' }}>{user.email || user.id}</div>
                </td>
                <td style={{ padding: '14px 16px' }}>Level {user.level || 1}</td>
                <td style={{ padding: '14px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: '999px', fontSize: '12px',
                    backgroundColor: user.onboardingComplete ? '#e6f9f0' : '#fff0f0',
                    color: user.onboardingComplete ? '#1a9e6a' : '#cc3333',
                  }}>
                    {user.onboardingComplete ? 'Yes' : 'No'}
                  </span>
                </td>
                <td style={{ padding: '14px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: '999px', fontSize: '12px',
                    backgroundColor: user.healthConnected ? '#e6f9f0' : '#f5f5f5',
                    color: user.healthConnected ? '#1a9e6a' : '#999',
                  }}>
                    {user.healthConnected ? 'Connected' : 'Not connected'}
                  </span>
                </td>
                <td style={{ padding: '14px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: '999px', fontSize: '12px',
                    backgroundColor: user.accountStatus === 'suspended' ? '#fff0f0' : '#e6f9f0',
                    color: user.accountStatus === 'suspended' ? '#cc3333' : '#1a9e6a',
                  }}>
                    {user.accountStatus === 'suspended' ? 'Suspended' : 'Active'}
                  </span>
                </td>
                <td style={{ padding: '14px 16px' }}>
                  <button
                    onClick={() => toggleSuspend(user.id, user.accountStatus)}
                    style={{
                      padding: '6px 14px', borderRadius: '6px', fontSize: '12px',
                      border: 'none', fontWeight: '500', cursor: 'pointer',
                      backgroundColor: user.accountStatus === 'suspended' ? '#e6f9f0' : '#fff0f0',
                      color: user.accountStatus === 'suspended' ? '#1a9e6a' : '#cc3333',
                    }}
                  >
                    {user.accountStatus === 'suspended' ? 'Reinstate' : 'Suspend'}
                  </button>

                  <button
                    onClick={() => handleDelete(user.id)}
                    style={{
                      padding: '6px 14px', borderRadius: '6px', fontSize: '12px',
                      border: 'none', backgroundColor: '#ffeeee', color: '#cc0000',
                      fontWeight: '500', marginLeft: '8px',
                    }}
                  >
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default Users;