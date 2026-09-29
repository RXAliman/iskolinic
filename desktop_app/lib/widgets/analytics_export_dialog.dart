import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../services/excel_export_service.dart';
import 'dart:io';

class AnalyticsExportDialog extends StatefulWidget {
  final String type; // 'symptoms' or 'supplies'

  const AnalyticsExportDialog({super.key, required this.type});

  @override
  State<AnalyticsExportDialog> createState() => _AnalyticsExportDialogState();
}

class _AnalyticsExportDialogState extends State<AnalyticsExportDialog> {
  late DateTime _startDate;
  late DateTime _endDate;

  final Map<String, bool> _departments = {
    'Pre-school': true,
    'Grade School': true,
    'Junior High School': true,
    'Senior High School': true,
    'College': true,
    'General': true,
  };

  final Map<String, bool> _expandDepartments = {
    'Pre-school': false,
    'Grade School': false,
    'Junior High School': false,
    'Senior High School': false,
    'College': false,
    'General': false,
  };

  bool _includeStudent = true;
  bool _includeEmployee = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _calculateDefaultRange();
  }

  void _calculateDefaultRange() {
    final now = DateTime.now();
    // School year: August to June
    if (now.month >= 8) {
      // Current year August to next year June
      _startDate = DateTime(now.year, 8, 1);
      _endDate = DateTime(now.year + 1, 6, 30);
    } else {
      // Last year August to current year June
      _startDate = DateTime(now.year - 1, 8, 1);
      _endDate = DateTime(now.year, 6, 30);
    }

    // Max is today
    if (_endDate.isAfter(now)) {
      _endDate = now;
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: isStart ? DateTime(2020) : _startDate,
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _export() async {
    final String defaultFileName = widget.type == 'symptoms'
        ? 'Symptoms_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx'
        : 'Supplies_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

    final String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Report',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile == null) return; // User canceled

    setState(() => _isExporting = true);

    try {
      String? path;
      if (widget.type == 'symptoms') {
        path = await ExcelExportService.instance.exportSymptomsReport(
          startDate: _startDate,
          endDate: _endDate,
          departments: _departments,
          expandDepartments: _expandDepartments,
          includeStudent: _includeStudent,
          includeEmployee: _includeEmployee,
          savePath: outputFile,
        );
      } else {
        path = await ExcelExportService.instance.exportSuppliesReport(
          startDate: _startDate,
          endDate: _endDate,
          departments: _departments,
          expandDepartments: _expandDepartments,
          includeStudent: _includeStudent,
          includeEmployee: _includeEmployee,
          savePath: outputFile,
        );
      }

      if (mounted) {
        setState(() => _isExporting = false);
        if (path != null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Report exported to: $path'),
              action: SnackBarAction(
                label: 'Open Folder',
                onPressed: () {
                  final folder = Directory(path!).parent.path;
                  if (Platform.isWindows) {
                    Process.run('explorer.exe', [folder]);
                  }
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to export report')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.file_download_outlined,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.type == 'symptoms'
                      ? 'Export Symptoms Report'
                      : 'Export Supplies Report',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Date Range
            Text('Date Range', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Text(DateFormat('MMM dd, yyyy').format(_startDate)),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('to'),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Text(DateFormat('MMM dd, yyyy').format(_endDate)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Roles
            Text('Roles', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      title:
                          const Text('Student', style: TextStyle(fontSize: 14)),
                      value: _includeStudent,
                      onChanged: (val) {
                        setState(() => _includeStudent = val ?? false);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text(
                        'Employee',
                        style: TextStyle(fontSize: 14),
                      ),
                      value: _includeEmployee,
                      onChanged: (val) {
                        setState(() => _includeEmployee = val ?? false);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Departments
            Text('Departments', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                children: _departments.keys.map((dept) {
                  final bool isEnabled = _includeStudent || _includeEmployee;

                  return IgnorePointer(
                    ignoring: !isEnabled,
                    child: Opacity(
                      opacity: isEnabled ? 1.0 : 0.4,
                      child: CheckboxListTile(
                        title: Text(dept, style: const TextStyle(fontSize: 14)),
                        value: isEnabled ? _departments[dept] : false,
                        onChanged: (val) {
                          setState(() => _departments[dept] = val ?? false);
                        },
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Expand',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Checkbox(
                              value: isEnabled
                                  ? _expandDepartments[dept]
                                  : false,
                              onChanged: isEnabled && _departments[dept] == true
                                  ? (val) {
                                      setState(
                                        () =>
                                            _expandDepartments[dept] =
                                                val ?? false,
                                      );
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        dense: true,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isExporting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isExporting ? null : _export,
                  child: _isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Export Excel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
