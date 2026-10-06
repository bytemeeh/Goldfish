# Feedback reporting

Feedback is available from Settings → Help & feedback as “Report a bug” or “Share an idea”. The database recovery screen also provides a “Report a problem” entry. The form keeps the message required while making reproduction steps, expected result, screen or feature, screenshot, and app details optional. The app details toggle controls the allowlisted version, device, and operating-system fields.

An optional image is prepared locally before it becomes an attachment. Input is limited to 25 MB, the image is downsampled to a maximum dimension of 2,048 pixels, and the output JPEG is limited to 5 MB. A fresh JPEG is produced so source photo metadata, including location and camera fields, is not carried into the attachment.

Mail is offered only when `FeedbackSupportEmail` is a validated single address and Mail is available on the device. The configured support address is `goldfish.pond.app@gmail.com` in both `Goldfish/Info.plist` and `project.yml`. Share and Copy remain available when Mail is unavailable.

Share and Copy are always available as local handoff choices. Nothing is transmitted automatically. The feature has no server backend, account, or background submission. Mail cancellation, saving a draft, sending, or failure returns to the form and preserves the report fields for another choice.

Recent view-switch history is separately opt-in and off by default. A maximum of 40 fixed events is kept in memory and discarded when the app exits. Events record a requested destination, a committed mode change, or a destination appearing. The form captures a stable snapshot when opened and previews the exact labels included in the report. No contact identifiers, names, search text, touch coordinates, or database contents are recorded. Nothing is submitted automatically.

These events can distinguish a recognized request from a completed navigation, but cannot prove that a touch never reached the button. Reporting a problem in chat remains useful; a report with interaction history can provide additional evidence after reproducing it.

Current implementation checks are recorded in `POND_FOCUS_IMPLEMENTATION.md`. No actual feedback report was sent during verification.

## Manual acceptance checklist

- Open Help & feedback from Settings and confirm both bug and idea entry points; open Report a problem from database recovery.
- Confirm a message is required, optional fields can be omitted, and switching between bug and idea does not include hidden bug fields.
- Toggle app details off and confirm the copied or shared text contains no automatic version, device, or operating-system fields.
- Choose an image, confirm it is shown as an attachment, and verify a large image is downsampled and stays within the stated limits.
- Verify Mail appears only when the device can send Mail; verify Share and Copy remain available.
- Switch between Pond and List, open a report, and confirm history is off by default. Opt in and inspect its preview; verify it matches the copied report.
- Turn history off and verify it is absent from the report. App details and interaction history have independent controls.
- Cancel or fail the Mail composer and confirm the form remains populated and offers the fallback actions.
