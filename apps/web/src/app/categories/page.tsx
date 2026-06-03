'use client';

import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { Category, CategoryKind } from '@1wallet/domain/types';
import { useState, useMemo } from 'react';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { Input, Select } from '../../components/Input';
import { Modal } from '../../components/Modal';

export default function CategoriesPage() {
  const { state, ready, addCategory, editCategory } = useLedger();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  
  // Form state
  const [name, setName] = useState('');
  const [kind, setKind] = useState<CategoryKind>('expense');
  const [parentId, setParentId] = useState('');
  
  const categories = useMemo(() => ready ? state.categories : [], [ready, state]);
  
  const rootCategories = categories.filter(c => !c.parentId && !c.isArchived);
  const getSubcategories = (id: string) => categories.filter(c => c.parentId === id && !c.isArchived);

  if (!ready) return <p>Loading…</p>;

  const handleOpenModal = (category?: Category) => {
    if (category) {
      setEditingCategory(category);
      setName(category.name);
      setKind(category.kind);
      setParentId(category.parentId || '');
    } else {
      setEditingCategory(null);
      setName('');
      setKind('expense');
      setParentId('');
    }
    setIsModalOpen(true);
  };

  const handleSave = async () => {
    if (!name.trim()) return;

    if (editingCategory) {
      await editCategory(editingCategory.id, {
        name: name.trim(),
        kind,
        parentId: parentId || undefined
      });
    } else {
      await addCategory({
        name: name.trim(),
        kind,
        parentId: parentId || undefined
      });
    }
    setIsModalOpen(false);
  };

  const toggleArchive = async (id: string, currentArchived: boolean) => {
    await editCategory(id, { isArchived: !currentArchived });
  };

  const renderCategoryList = (kindFilter: CategoryKind) => {
    const roots = rootCategories.filter(c => c.kind === kindFilter);
    
    if (roots.length === 0) return <p style={{ color: 'var(--color-on-surface-variant)' }}>No {kindFilter} categories yet.</p>;

    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.sm }}>
        {roots.map(cat => {
          const subs = getSubcategories(cat.id);
          return (
            <div key={cat.id} style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}>
              <div 
                style={{ 
                  display: 'flex', 
                  justifyContent: 'space-between', 
                  alignItems: 'center',
                  padding: tokens.space.md,
                  backgroundColor: 'var(--color-surface)',
                  borderRadius: tokens.radius.md,
                  border: '1px solid var(--color-outline-variant)'
                }}
              >
                <span style={{ fontWeight: 600 }}>{cat.name}</span>
                <div style={{ display: 'flex', gap: tokens.space.xs }}>
                  <Button variant="ghost" onClick={() => handleOpenModal(cat)} style={{ padding: '4px 8px' }}>Edit</Button>
                  <Button variant="ghost" onClick={() => toggleArchive(cat.id, cat.isArchived)} style={{ padding: '4px 8px', color: 'var(--color-error)' }}>Archive</Button>
                </div>
              </div>
              
              {/* Subcategories */}
              {subs.length > 0 && (
                <div style={{ paddingLeft: tokens.space.xl, display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}>
                  {subs.map(sub => (
                    <div 
                      key={sub.id}
                      style={{ 
                        display: 'flex', 
                        justifyContent: 'space-between', 
                        alignItems: 'center',
                        padding: tokens.space.sm,
                        backgroundColor: 'var(--color-surface-low)',
                        borderRadius: tokens.radius.sm,
                      }}
                    >
                      <span style={{ fontSize: tokens.font.size.sm }}>{sub.name}</span>
                      <div style={{ display: 'flex', gap: tokens.space.xs }}>
                        <Button variant="ghost" onClick={() => handleOpenModal(sub)} style={{ padding: '2px 8px', fontSize: tokens.font.size.xs }}>Edit</Button>
                        <Button variant="ghost" onClick={() => toggleArchive(sub.id, sub.isArchived)} style={{ padding: '2px 8px', fontSize: tokens.font.size.xs, color: 'var(--color-error)' }}>Archive</Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    );
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Categories</h1>
        <Button onClick={() => handleOpenModal()}>Add Category</Button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))', gap: tokens.space.lg }}>
        <Card title="Expense Categories">
          {renderCategoryList('expense')}
        </Card>
        <Card title="Income Categories">
          {renderCategoryList('income')}
        </Card>
      </div>

      <Modal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title={editingCategory ? 'Edit Category' : 'Add Category'}
        actions={
          <>
            <Button variant="secondary" onClick={() => setIsModalOpen(false)}>Cancel</Button>
            <Button onClick={handleSave}>Save</Button>
          </>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
          <Input 
            label="Name" 
            placeholder="e.g. Groceries" 
            value={name} 
            onChange={e => setName(e.target.value)} 
          />
          <Select 
            label="Type" 
            value={kind} 
            onChange={e => setKind(e.target.value as CategoryKind)}
          >
            <option value="expense">Expense</option>
            <option value="income">Income</option>
          </Select>
          <Select
            label="Parent Category (Optional)"
            value={parentId}
            onChange={e => setParentId(e.target.value)}
          >
            <option value="">None (Top level)</option>
            {rootCategories.filter(c => c.kind === kind && c.id !== editingCategory?.id).map(c => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </Select>
        </div>
      </Modal>
    </div>
  );
}
