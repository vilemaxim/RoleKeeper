# 🧠 Task Learnings
**Task:** 001
**Role:** CODER

RadioGroup migration gotchas worth documenting: (1) RadioGroup.onChanged is non-nullable ValueChanged<T?>, unlike the old per-tile onChanged which accepted null to disable; the disabled-state must move to RadioListTile.enabled. (2) RadioGroup wraps a single Widget (typically a Column or ListView), so spread-into-children patterns need to be reshaped into a wrapped child. (3) Removing rules from analyzer.errors can leave an empty `errors:` map that itself triggers invalid_section_format; remove the whole `analyzer:` block when it becomes empty.
