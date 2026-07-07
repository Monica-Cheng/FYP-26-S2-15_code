import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs } from 'firebase/firestore';

function StatCard({ title, value, sub, color }) {
  return (
    <div style={{
      backgroundColor: 'white',
      borderRadius: '12px',
      padding: '24px',
      flex: 1,
      borderTop: `4px solid ${color}`,
    }}>
      <div style={{ fontSize: '13px', color: '#888', marginBottom: '8px' }}>{title}</div>
      <div style={{ fontSize: '32px', fontWeight: '700', color: '#1a1a2e' }}>{value}</div>
      <div style={{ fontSize: '13px', color: '#aaa', marginTop: '4px' }}>{sub}</div>
    </div>
  );
}

function Dashboard() {
  const [stats, setStats] = useState({
    totalUsers: 0,
    totalPlans: 0,
    totalExercises: 0,
    pendingBP: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const [usersSnap, plansSnap, exercisesSnap, bpSnap] = await Promise.all([
          getDocs(collection(db, 'users')),
          getDocs(collection(db, 'plans')),
          getDocs(collection(db, 'exercises')),
          getDocs(collection(db, 'businessPartners')),
        ]);

        const pendingBP = bpSnap.docs.filter(doc => doc.data().status === 'pending').length;

        setStats({
          totalUsers: usersSnap.size,
          totalPlans: plansSnap.size,
          totalExercises: exercisesSnap.size,
          pendingBP,
        });
      } catch (err) {
        console.error('Error fetching stats:', err);
      }
      setLoading(false);
    };

    fetchStats();
  }, []);

  if (loading) return <div style={{ fontSize: '14px', color: '#888' }}>Loading dashboard...</div>;

  return (
    <div>
      <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>Dashboard</h1>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '32px' }}>
        {new Date().toDateString()}
      </p>

      <div style={{ display: 'flex', gap: '20px', marginBottom: '32px', flexWrap: 'wrap' }}>
        <StatCard title="Total Users" value={stats.totalUsers} sub="registered accounts" color="#6c63ff" />
        <StatCard title="Total Plans" value={stats.totalPlans} sub="in plan library" color="#48cae4" />
        <StatCard title="Total Exercises" value={stats.totalExercises} sub="in exercise library" color="#06d6a0" />
        <StatCard title="Pending BP Approvals" value={stats.pendingBP} sub="awaiting review" color="#ff6b6b" />
      </div>

      <div style={{
        backgroundColor: 'white',
        borderRadius: '12px',
        padding: '24px',
      }}>
        <h2 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '16px' }}>Quick Actions</h2>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
          {[
            { label: 'Review BP Applications', color: '#6c63ff' },
            { label: 'Manage Users', color: '#48cae4' },
            { label: 'Add Exercise', color: '#06d6a0' },
            { label: 'Configure XP Settings', color: '#ff6b6b' },
          ].map(action => (
            <button
              key={action.label}
              style={{
                padding: '10px 20px',
                backgroundColor: action.color,
                color: 'white',
                border: 'none',
                borderRadius: '8px',
                fontSize: '13px',
                fontWeight: '500',
              }}
            >
              {action.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

export default Dashboard;