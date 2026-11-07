import 'package:flutter/material.dart';

/// Catalogue of everything a patient can track.
/// Add a new tracker type here and it appears everywhere (plan, chat, cards).
class TrackerDef {
  const TrackerDef({
    required this.kind,
    required this.label,
    required this.icon,
    required this.color,
    this.unit = '',
    this.slots = const {},
    this.defaultFrequency = 'daily',
    this.numeric = true,
  });
  final String kind;
  final String label;
  final IconData icon;
  final Color color;
  final String unit;
  final Map<String, String> slots; // key → label
  final String defaultFrequency;
  final bool numeric;
}

class Trackers {
  static const sugarSlots = {
    'fasting': 'Fasting',
    'after_breakfast': '2 hrs after breakfast',
    'after_lunch': '2 hrs after lunch',
    'after_dinner': '2 hrs after dinner',
    'random': 'Any time',
  };
  static const mealSlots = {
    'breakfast': 'Breakfast',
    'lunch': 'Lunch',
    'dinner': 'Dinner',
    'snack': 'Snack',
  };

  static const all = <String, TrackerDef>{
    'sugar': TrackerDef(
        kind: 'sugar', label: 'Blood sugar', icon: Icons.bloodtype_outlined,
        color: Color(0xFFB4533F), unit: 'mg/dL', slots: sugarSlots),
    'diet': TrackerDef(
        kind: 'diet', label: 'Diet', icon: Icons.restaurant_outlined,
        color: Color(0xFF678778), slots: mealSlots, numeric: false),
    'weight': TrackerDef(
        kind: 'weight', label: 'Weight', icon: Icons.monitor_weight_outlined,
        color: Color(0xFF3C5761), unit: 'kg'),
    'waist': TrackerDef(
        kind: 'waist', label: 'Waist circumference', icon: Icons.straighten,
        color: Color(0xFF6E5A80), unit: 'cm', defaultFrequency: 'weekly'),
    'hip': TrackerDef(
        kind: 'hip', label: 'Hip circumference', icon: Icons.straighten,
        color: Color(0xFF6E5A80), unit: 'cm', defaultFrequency: 'weekly'),
    'bp': TrackerDef(
        kind: 'bp', label: 'Blood pressure', icon: Icons.favorite_border,
        color: Color(0xFFB0693E), unit: 'mmHg',
        slots: {'morning': 'Morning', 'evening': 'Evening', 'random': 'Any time'}),
    'spo2': TrackerDef(
        kind: 'spo2', label: 'SpO2', icon: Icons.air, color: Color(0xFF2F7480), unit: '%'),
    'periods': TrackerDef(
        kind: 'periods', label: 'Periods', icon: Icons.water_drop_outlined,
        color: Color(0xFFB4533F), defaultFrequency: 'as_needed', numeric: false),
    'sleep': TrackerDef(
        kind: 'sleep', label: 'Sleep', icon: Icons.bedtime_outlined,
        color: Color(0xFF2C3A45), numeric: false),
    'water': TrackerDef(
        kind: 'water', label: 'Water', icon: Icons.local_drink_outlined,
        color: Color(0xFF2F7480), unit: 'glasses'),
    'exercise': TrackerDef(
        kind: 'exercise', label: 'Exercise', icon: Icons.directions_walk,
        color: Color(0xFF4F7564), unit: 'min'),
    'symptoms': TrackerDef(
        kind: 'symptoms', label: 'Symptoms', icon: Icons.sick_outlined,
        color: Color(0xFFC08A2E), defaultFrequency: 'as_needed', numeric: false),
    'custom': TrackerDef(
        kind: 'custom', label: 'Custom', icon: Icons.tune, color: Color(0xFF7A8A92)),
  };

  static TrackerDef def(String kind) => all[kind] ?? all['custom']!;

  static const frequencies = {
    'daily': 'Daily',
    'alternate': 'Alternate days',
    'weekly': 'Weekly',
    'days': 'Chosen days',
    'as_needed': 'When needed',
  };

  /// Quick templates: tracker kind → default slots.
  static const templates = <String, Map<String, List<String>>>{
    'Diabetes': {
      'sugar': ['fasting', 'after_lunch'],
      'diet': ['breakfast', 'lunch', 'dinner'],
      'weight': [],
    },
    'PCOD': {
      'periods': [],
      'weight': [],
      'waist': [],
      'hip': [],
      'diet': ['breakfast', 'lunch', 'dinner'],
    },
    'Weight loss': {
      'weight': [],
      'waist': [],
      'diet': ['breakfast', 'lunch', 'dinner', 'snack'],
      'water': [],
      'exercise': [],
    },
  };

  /// Default reminder times for slots.
  static const slotReminder = {
    'fasting': '07:00',
    'after_breakfast': '10:30',
    'after_lunch': '15:00',
    'after_dinner': '22:00',
    'breakfast': '09:30',
    'lunch': '14:00',
    'dinner': '21:00',
    'morning': '08:00',
    'evening': '19:00',
  };

  /// One-line summary of an entry's values, for cards and lists.
  static String summary(String kind, Map data) {
    String v(String k) => (data[k] ?? '').toString();
    switch (kind) {
      case 'bp':
        return '${v('systolic')}/${v('diastolic')}${v('pulse').isEmpty ? '' : ' · pulse ${v('pulse')}'}';
      case 'diet':
      case 'symptoms':
        return v('text');
      case 'periods':
        return [
          v('event') == 'ended' ? 'Period ended' : 'Period started',
          if (v('flow').isNotEmpty) 'flow ${v('flow')}',
          if (v('pain').isNotEmpty) 'pain ${v('pain')}',
          if (v('text').isNotEmpty) v('text'),
        ].join(' · ');
      case 'sleep':
        return [
          if (v('bed').isNotEmpty) 'Bed ${v('bed')}',
          if (v('wake').isNotEmpty) 'woke ${v('wake')}',
          if (v('quality').isNotEmpty) v('quality'),
        ].join(' · ');
      case 'exercise':
        return '${v('value')} min${v('text').isEmpty ? '' : ' · ${v('text')}'}';
      default:
        return v('value');
    }
  }
}
