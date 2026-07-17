import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, addDoc, deleteDoc, doc, updateDoc } from 'firebase/firestore';
import * as XLSX from 'xlsx';

function Exercises() {
  const [exercises, setExercises] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState({ name: '', muscleGroup: '', equipment: '', difficulty: 'Beginner' });
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const fetchExercises = async () => {
      try {
        const snap = await getDocs(collection(db, 'exercises'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setExercises(data);
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchExercises();
  }, []);

  const handleAdd = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      if (editingId) {
        await updateDoc(doc(db, 'exercises', editingId), form);
        setExercises(prev => prev.map(e => e.id === editingId ? { ...e, ...form } : e));
        setEditingId(null);
      } else {
        const docRef = await addDoc(collection(db, 'exercises'), {
          ...form,
          createdAt: new Date().toISOString(),
        });
        setExercises(prev => [...prev, { id: docRef.id, ...form }]);
      }
      setForm({ name: '', muscleGroup: '', equipment: '', difficulty: 'Beginner' });
      setShowForm(false);
    } catch (err) {
      console.error(err);
    }
    setSaving(false);
  };

  const handleEdit = (ex) => {
    setForm({ name: ex.name || '', muscleGroup: ex.muscleGroup || '', equipment: ex.equipment || '', difficulty: ex.difficulty || 'Beginner' });
    setEditingId(ex.id);
    setShowForm(true);
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Delete this exercise?')) return;
    await deleteDoc(doc(db, 'exercises', id));
    setExercises(prev => prev.filter(e => e.id !== id));
  };

  const handleExcelUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = async (evt) => {
      const workbook = XLSX.read(evt.target.result, { type: 'binary' });
      const sheet = workbook.Sheets[workbook.SheetNames[0]];
      const rows = XLSX.utils.sheet_to_json(sheet);
      let added = 0;
      for (const row of rows) {
        const exercise = {
          name: row['name'] || row['Name'] || '',
          muscleGroup: row['muscleGroup'] || row['Muscle Group'] || '',
          equipment: row['equipment'] || row['Equipment'] || '',
          difficulty: row['difficulty'] || row['Difficulty'] || 'Beginner',
          createdAt: new Date().toISOString(),
        };
        if (!exercise.name) continue;
        const docRef = await addDoc(collection(db, 'exercises'), exercise);
        setExercises(prev => [...prev, { id: docRef.id, ...exercise }]);
        added++;
      }
      alert(`Successfully uploaded ${added} exercises.`);
    };
    reader.readAsBinaryString(file);
  };

  const filtered = exercises.filter(e =>
    (e.name || '').toLowerCase().includes(search.toLowerCase()) ||
    (e.muscleGroup || '').toLowerCase().includes(search.toLowerCase())
  );

  if (loading) return <div style={{ color: '#888', fontSize: '14px' }}>Loading exercises...</div>;

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
        <h1 style={{ fontSize: '24px', fontWeight: '700' }}>Exercises</h1>
        <div style={{ display: 'flex', gap: '12px' }}>
          <button
            onClick={() => { setShowForm(!showForm); setEditingId(null); setForm({ name: '', muscleGroup: '', equipment: '', difficulty: 'Beginner' }); }}
            style={{ padding: '10px 20px', borderRadius: '8px', border: 'none', backgroundColor: '#6c63ff', color: 'white', fontSize: '14px', fontWeight: '500', cursor: 'pointer' }}
          >
            + Add Exercise
          </button>
          <label style={{
            padding: '10px 20px', borderRadius: '8px', border: 'none',
            backgroundColor: '#06d6a0', color: 'white', fontSize: '14px',
            fontWeight: '500', cursor: 'pointer',
          }}>
            📤 Upload Excel
            <input
              type="file"
              accept=".xlsx,.xls,.csv"
              style={{ display: 'none' }}
              onChange={handleExcelUpload}
            />
          </label>
        </div>
      </div>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '24px' }}>{exercises.length} exercises in library</p>

      {showForm && (
        <div style={{ backgroundColor: 'white', borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
          <h2 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '16px' }}>
            {editingId ? 'Edit Exercise' : 'New Exercise'}
          </h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {[
              { label: 'Exercise Name', key: 'name', placeholder: 'e.g. Bench Press' },
              { label: 'Muscle Group', key: 'muscleGroup', placeholder: 'e.g. Chest' },
              { label: 'Equipment', key: 'equipment', placeholder: 'e.g. Barbell' },
            ].map(field => (
              <div key={field.key}>
                <label style={{ fontSize: '13px', color: '#555', display: 'block', marginBottom: '4px' }}>{field.label}</label>
                <input
                  value={form[field.key]}
                  onChange={e => setForm(prev => ({ ...prev, [field.key]: e.target.value }))}
                  placeholder={field.placeholder}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid #ddd', fontSize: '14px', outline: 'none' }}
                />
              </div>
            ))}
            <div>
              <label style={{ fontSize: '13px', color: '#555', display: 'block', marginBottom: '4px' }}>Difficulty</label>
              <select
                value={form.difficulty}
                onChange={e => setForm(prev => ({ ...prev, difficulty: e.target.value }))}
                style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid #ddd', fontSize: '14px', outline: 'none' }}
              >
                <option>Beginner</option>
                <option>Intermediate</option>
                <option>Advanced</option>
              </select>
            </div>
            <div style={{ display: 'flex', gap: '12px' }}>
              <button
                onClick={handleAdd}
                disabled={saving}
                style={{ padding: '10px 24px', borderRadius: '8px', border: 'none', backgroundColor: '#6c63ff', color: 'white', fontSize: '14px', fontWeight: '500' }}
              >
                {saving ? 'Saving...' : editingId ? 'Update Exercise' : 'Save Exercise'}
              </button>
              <button
                onClick={() => { setShowForm(false); setEditingId(null); }}
                style={{ padding: '10px 24px', borderRadius: '8px', border: '1px solid #ddd', backgroundColor: 'white', fontSize: '14px' }}
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      <input
        placeholder="Search exercises..."
        value={search}
        onChange={e => setSearch(e.target.value)}
        style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid #ddd', fontSize: '14px', marginBottom: '20px', outline: 'none' }}
      />

      <div style={{ backgroundColor: 'white', borderRadius: '12px', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '14px' }}>
          <thead>
            <tr style={{ backgroundColor: '#f8f8f8', borderBottom: '1px solid #eee' }}>
              {['Name', 'Muscle Group', 'Equipment', 'Difficulty', 'Action'].map(h => (
                <th key={h} style={{ padding: '14px 16px', textAlign: 'left', fontWeight: '600', color: '#555' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filtered.map(ex => (
              <tr key={ex.id} style={{ borderBottom: '1px solid #f0f0f0' }}>
                <td style={{ padding: '14px 16px', fontWeight: '500' }}>{ex.name || '—'}</td>
                <td style={{ padding: '14px 16px', color: '#666' }}>{ex.muscleGroup || '—'}</td>
                <td style={{ padding: '14px 16px', color: '#666' }}>{ex.equipment || '—'}</td>
                <td style={{ padding: '14px 16px' }}>
                  <span style={{
                    padding: '3px 10px', borderRadius: '999px', fontSize: '12px',
                    backgroundColor: ex.difficulty === 'Advanced' ? '#fff0f0' : ex.difficulty === 'Intermediate' ? '#fff8e6' : '#e6f9f0',
                    color: ex.difficulty === 'Advanced' ? '#cc3333' : ex.difficulty === 'Intermediate' ? '#cc8800' : '#1a9e6a',
                  }}>
                    {ex.difficulty || 'Beginner'}
                  </span>
                </td>
                <td style={{ padding: '14px 16px', display: 'flex', gap: '8px' }}>
                  <button
                    onClick={() => handleEdit(ex)}
                    style={{ padding: '6px 14px', borderRadius: '6px', fontSize: '12px', border: 'none', backgroundColor: '#f0f0ff', color: '#6c63ff', fontWeight: '500' }}
                  >
                    Edit
                  </button>
                  <button
                    onClick={() => handleDelete(ex.id)}
                    style={{ padding: '6px 14px', borderRadius: '6px', fontSize: '12px', border: 'none', backgroundColor: '#fff0f0', color: '#cc3333', fontWeight: '500' }}
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

export default Exercises;