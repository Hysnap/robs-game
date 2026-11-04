# How to add crime-variant configuration

`crime/` is an optional overlay. Its `business_rules.cfg` is only used when
the crime variant is explicitly selected by the caller. Keep paths rooted at
`res://` and copy only the sections required by the variant.

For impact thresholds, use the local guides in `impacts/` and its child
directories. Validate the variant through the test that mounts it; core tests
do not automatically mount crime data.
