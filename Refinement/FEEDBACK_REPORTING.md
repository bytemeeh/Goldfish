# Feedback reporting

Feedback is available from Settings → Help & feedback as “Report a bug” or “Share an idea”. The database recovery screen also provides a “Report a problem” entry. The form keeps the message required while making reproduction steps, expected result, screen or feature, screenshot, and app details optional. The app details toggle controls the allowlisted version, device, and operating-system fields.

An optional image is prepared locally before it becomes an attachment. Input is limited to 25 MB, the image is downsampled to a maximum dimension of 2,048 pixels, and the output JPEG is limited to 5 MB. A fresh JPEG is produced so source photo metadata, including location and camera fields, is not carried into the attachment.

Mail is offered only when `FeedbackSupportEmail` is a validated single address and Mail is available on the device. The support address is intentionally blank in both `Goldfish/Info.plist` and `project.yml`; an owner must provide the inbox in both places before direct email is enabled. Until then, Share and Copy remain available and no inbox is assumed.

Share and Copy are always available as local handoff choices. Nothing is transmitted automatically. The feature has no server backend, account, or background submission. Mail cancellation, saving a draft, sending, or failure returns to the form and preserves the report fields for another choice.

Verification: the completed Goldfish suite executed 176 tests with 0 failures and 0 warnings. The exact log is in `Refinement/Feedback-Evidence/ios-tests.log`. No actual report was sent by the agent. Direct email remains disabled pending owner confirmation of the support address; `FeedbackSupportEmail` is currently empty.

## Manual acceptance checklist

- Open Help & feedback from Settings and confirm both bug and idea entry points; open Report a problem from database recovery.
- Confirm a message is required, optional fields can be omitted, and switching between bug and idea does not include hidden bug fields.
- Toggle app details off and confirm the copied or shared text contains no automatic version, device, or operating-system fields.
- Choose an image, confirm it is shown as an attachment, and verify a large image is downsampled and stays within the stated limits.
- With the blank `FeedbackSupportEmail`, confirm no direct Mail recipient is assumed and Share/Copy work.
- After configuring the owner inbox in both plist/project locations, verify Mail appears only when the device can send Mail; verify Share and Copy remain available.
- Cancel or fail the Mail composer and confirm the form remains populated and offers the fallback actions.
