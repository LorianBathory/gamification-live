# Live presentation setup

The static presentation can be hosted on GitHub Pages. Supabase stores the shared room state, enforces the 60-second participant cooldown, and sends realtime updates.

## URLs

- Audience: `https://YOUR-NAME.github.io/YOUR-REPOSITORY/?room=gamification-live`
- Presenter: `https://YOUR-NAME.github.io/YOUR-REPOSITORY/?room=gamification-live&presenter=1`

The presenter code is entered in the browser and stored only for the current tab.

## Supabase

1. Create a Supabase project.
2. Link this folder with the Supabase CLI.
3. Apply the migration in `supabase/migrations`.
4. Set the presenter code as a function secret:
   `supabase secrets set PRESENTER_TOKEN="your-long-random-code"`
5. Deploy `presentation-api`.
6. Put the project URL and publishable key in `presentation-config.js`, then set `syncEnabled` to `true`.

Never put the presenter code or Supabase secret key in `presentation-config.js`. The publishable key is safe to expose in a browser when database permissions are configured correctly.

## Before presenting

1. Open the audience URL in a private window or on a phone.
2. Open the presenter URL in your normal browser.
3. Use **Reset session** in presenter mode.
4. Verify slide synchronization and the 60-second button cooldown.
5. Keep the presenter tab open during the talk.
