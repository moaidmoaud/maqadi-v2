import 'package:flutter/material.dart';

import '../models/purchase_models.dart';
import '../services/store_service.dart';

class StoreManagementScreen extends StatefulWidget {
  const StoreManagementScreen({super.key, required this.service});

  final StoreService service;

  @override
  State<StoreManagementScreen> createState() => _StoreManagementScreenState();
}

class _StoreManagementScreenState extends State<StoreManagementScreen> {
  final _searchController = TextEditingController();
  List<Store> _stores = const [];
  StoreStatusFilter _filter = StoreStatusFilter.active;
  Object? _error;
  bool _loading = true;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_reloadWithoutSpinner);
    _initialize();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_reloadWithoutSpinner)
      ..dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await widget.service.initialize();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _reloadWithoutSpinner() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    final version = ++_loadVersion;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final stores = await widget.service.searchStores(
        query: _searchController.text,
        filter: _filter,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _stores = stores;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Store? store]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: StoreFormScreen(service: widget.service, store: store),
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _archive(Store store) async {
    final confirmed = await _confirm(
      title: 'أرشفة المتجر؟',
      message:
          'لن يظهر المتجر ضمن خيارات المشتريات الجديدة، وستبقى مشترياته السابقة محفوظة.',
      action: 'أرشفة',
      key: const ValueKey('confirm-archive-store'),
    );
    if (!confirmed) return;
    await _runAction(
        () => widget.service.setArchived(store.id, archived: true));
  }

  Future<void> _restore(Store store) =>
      _runAction(() => widget.service.setArchived(store.id, archived: false));

  Future<void> _delete(Store store) async {
    final confirmed = await _confirm(
      title: 'حذف المتجر نهائيًا؟',
      message: 'يسمح بالحذف فقط إذا لم يُستخدم المتجر في أي عملية شراء.',
      action: 'حذف',
      key: const ValueKey('confirm-delete-store'),
    );
    if (!confirmed) return;
    await _runAction(() => widget.service.deleteStore(store.id));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    required Key key,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: key,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on StoreValidationException catch (error) {
      _showMessage(error.message);
    } on StoreDeletionException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('تعذر تنفيذ العملية: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('store-management-screen'),
        appBar: AppBar(title: const Text('إدارة المتاجر')),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('add-store'),
          onPressed: _openForm,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('إضافة متجر'),
        ),
        body: Column(
          children: [
            _StoreFilters(
              searchController: _searchController,
              filter: _filter,
              onFilterChanged: (filter) {
                setState(() => _filter = filter);
                _load();
              },
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      );

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        key: ValueKey('store-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return _StoreError(error: _error!, onRetry: _initialize);
    }
    if (_stores.isEmpty) return const _StoreEmptyState();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _stores.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final store = _stores[index];
          return _StoreCard(
            store: store,
            onEdit: () => _openForm(store),
            onArchive: () => _archive(store),
            onRestore: () => _restore(store),
            onDelete: () => _delete(store),
          );
        },
      ),
    );
  }
}

class StoreFormScreen extends StatefulWidget {
  const StoreFormScreen({
    super.key,
    required this.service,
    this.store,
  });

  final StoreService service;
  final Store? store;

  @override
  State<StoreFormScreen> createState() => _StoreFormScreenState();
}

class _StoreFormScreenState extends State<StoreFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _branchController;
  late final TextEditingController _notesController;
  bool _busy = false;

  bool get _editing => widget.store != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.store?.name ?? '');
    _branchController = TextEditingController(text: widget.store?.branch ?? '');
    _notesController = TextEditingController(text: widget.store?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _branchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_editing) {
        await widget.service.updateStore(
          storeId: widget.store!.id,
          name: _nameController.text,
          branch: _branchController.text,
          notes: _notesController.text,
        );
      } else {
        await widget.service.createStore(
          name: _nameController.text,
          branch: _branchController.text,
          notes: _notesController.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on StoreValidationException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('تعذر حفظ المتجر: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('store-form-screen'),
        appBar: AppBar(title: Text(_editing ? 'تعديل المتجر' : 'إضافة متجر')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('store-name'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم المتجر *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('store-branch'),
              controller: _branchController,
              decoration: const InputDecoration(
                labelText: 'الفرع (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('store-notes'),
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const ValueKey('save-store'),
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('حفظ المتجر'),
          ),
        ),
      );
}

class _StoreFilters extends StatelessWidget {
  const _StoreFilters({
    required this.searchController,
    required this.filter,
    required this.onFilterChanged,
  });

  final TextEditingController searchController;
  final StoreStatusFilter filter;
  final ValueChanged<StoreStatusFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                key: const ValueKey('store-search'),
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'بحث باسم المتجر',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<StoreStatusFilter>(
                key: const ValueKey('store-status-filter'),
                segments: const [
                  ButtonSegment(
                    value: StoreStatusFilter.active,
                    label: Text('نشطة'),
                  ),
                  ButtonSegment(
                    value: StoreStatusFilter.archived,
                    label: Text('مؤرشفة'),
                  ),
                  ButtonSegment(
                    value: StoreStatusFilter.all,
                    label: Text('الكل'),
                  ),
                ],
                selected: {filter},
                onSelectionChanged: (selection) =>
                    onFilterChanged(selection.single),
              ),
            ],
          ),
        ),
      );
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.store,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  final Store store;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          key: ValueKey('store-${store.id}'),
          leading: CircleAvatar(
            child: Icon(
              store.isActive ? Icons.storefront_outlined : Icons.inventory_2,
            ),
          ),
          title: Text(
            store.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            [
              if (store.branch case final branch?) branch,
              if (!store.isActive) 'مؤرشف',
            ].join(' • '),
          ),
          onTap: onEdit,
          trailing: PopupMenuButton<String>(
            key: ValueKey('store-actions-${store.id}'),
            onSelected: (action) => switch (action) {
              'edit' => onEdit(),
              'archive' => onArchive(),
              'restore' => onRestore(),
              'delete' => onDelete(),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
              if (store.isActive)
                const PopupMenuItem(value: 'archive', child: Text('أرشفة'))
              else
                const PopupMenuItem(value: 'restore', child: Text('استعادة')),
              const PopupMenuItem(value: 'delete', child: Text('حذف')),
            ],
          ),
        ),
      );
}

class _StoreEmptyState extends StatelessWidget {
  const _StoreEmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        key: ValueKey('store-empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 64),
              SizedBox(height: 12),
              Text('لا توجد متاجر مطابقة'),
            ],
          ),
        ),
      );
}

class _StoreError extends StatelessWidget {
  const _StoreError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        key: const ValueKey('store-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 10),
              Text('تعذر تحميل المتاجر: $error'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}
