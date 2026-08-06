defmodule GamesTutor.Emails do
  @moduledoc "Transactional emails: confirmation (magic link), password reset, account bans."
  import Swoosh.Email

  @appeal_email "pete@cyberiad.ai"

  defp from_address, do: Application.fetch_env!(:games_tutor, :mail_from)
  defp frontend_url, do: Application.fetch_env!(:games_tutor, :frontend_base_url)

  # SendGrid rewrites every link in an email to go through its own click-tracking
  # redirector (u<id>.ct.sendgrid.net) by default. Chained behind Gmail's own
  # link-scanning wrapper (www.google.com/url?q=...), that two-hop redirect was
  # observed live to hang indefinitely for a magic-link URL pointing at a plain
  # HTTP+raw-IP dev address -- confirmed via SendGrid's own Activity API that the
  # underlying email really was delivered, so the failure is specifically in the
  # click-tracking redirect chain, not delivery. Disabling click tracking makes
  # the emailed link the real URL directly.
  defp no_click_tracking, do: %{click_tracking: %{enable: false}}

  def confirmation_email(user, raw_token) do
    url = "#{frontend_url()}/confirm-email?token=#{URI.encode_www_form(raw_token)}"

    new()
    |> to({user.display_name || user.email, user.email})
    |> from({"games_tutor", from_address()})
    |> subject("Confirm your games_tutor account")
    |> html_body(button_html(
      "Confirm your email",
      "Welcome to games_tutor! Click the button below to confirm your account and start playing.",
      url,
      "Confirm my account"
    ))
    |> text_body("Confirm your games_tutor account: #{url}")
    |> put_provider_option(:tracking_settings, no_click_tracking())
  end

  def reset_password_email(user, raw_token) do
    url = "#{frontend_url()}/reset-password?token=#{URI.encode_www_form(raw_token)}"

    new()
    |> to({user.display_name || user.email, user.email})
    |> from({"games_tutor", from_address()})
    |> subject("Reset your games_tutor password")
    |> html_body(button_html(
      "Reset your password",
      "We received a request to reset your games_tutor password. If you didn't make this request, you can safely ignore this email -- your password won't change.",
      url,
      "Reset my password"
    ))
    |> text_body("Reset your games_tutor password: #{url} (ignore this email if you didn't request it)")
    |> put_provider_option(:tracking_settings, no_click_tracking())
  end

  def account_banned_email(user) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({"games_tutor", from_address()})
    |> subject("Your games_tutor account has been suspended")
    |> html_body(notice_html(user.ban_reason))
    |> text_body(
      "Your games_tutor account has been suspended.\n\n" <>
        "Reason: #{user.ban_reason}\n\n" <>
        "If you believe this was a mistake, you can appeal by emailing #{@appeal_email}."
    )
    |> put_provider_option(:tracking_settings, no_click_tracking())
  end

  defp notice_html(reason) do
    """
    <!DOCTYPE html>
    <html>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f4f4f5; margin: 0; padding: 40px 20px;">
      <div style="max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 12px; padding: 32px;">
        <h1 style="font-size: 20px; color: #111827; margin: 0 0 16px;">Your account has been suspended</h1>
        <p style="font-size: 15px; color: #4b5563; line-height: 1.5; margin: 0 0 16px;">
          Your games_tutor account has been suspended for the following reason:
        </p>
        <p style="font-size: 15px; color: #111827; line-height: 1.5; margin: 0 0 24px; padding: 12px 16px; background: #f9fafb; border-radius: 8px; border-left: 3px solid #dc2626;">
          #{Plug.HTML.html_escape(reason)}
        </p>
        <p style="font-size: 15px; color: #4b5563; line-height: 1.5; margin: 0;">
          If you believe this was a mistake, you can appeal by emailing
          <a href="mailto:#{@appeal_email}" style="color: #4f46e5;">#{@appeal_email}</a>.
        </p>
      </div>
    </body>
    </html>
    """
  end

  defp button_html(heading, body_text, url, button_text) do
    """
    <!DOCTYPE html>
    <html>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f4f4f5; margin: 0; padding: 40px 20px;">
      <div style="max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 12px; padding: 32px;">
        <h1 style="font-size: 20px; color: #111827; margin: 0 0 16px;">#{heading}</h1>
        <p style="font-size: 15px; color: #4b5563; line-height: 1.5; margin: 0 0 24px;">#{body_text}</p>
        <a href="#{url}" style="display: inline-block; background: #4f46e5; color: #ffffff; text-decoration: none; font-weight: 600; font-size: 15px; padding: 12px 24px; border-radius: 8px;">#{button_text}</a>
        <p style="font-size: 13px; color: #9ca3af; margin: 24px 0 0;">If the button doesn't work, copy and paste this link into your browser:<br>#{url}</p>
      </div>
    </body>
    </html>
    """
  end
end
