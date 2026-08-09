require 'test_helper'

class RodauthMailerTest < ActionMailer::TestCase
  test 'reset password email renders transactional html template' do
    account = accounts(:customer_admin)
    email = RodauthMailer.reset_password(nil, account.id, 'test-reset-key')

    assert_equal [account.email], email.to
    assert_match(/Reset|Passwort/i, email.subject)

    html_body = email.html_part.body.to_s
    assert_match 'Amplifa', html_body
    assert_match 'button', html_body
    assert_match '/reset-password?key=', html_body
    assert_not_nil email.text_part
  end

  test 'verify account email renders branded transactional template' do
    account = accounts(:customer_admin)
    email = RodauthMailer.verify_account(nil, account.id, 'test-verify-key')

    assert_equal [account.email], email.to
    assert_match(/Activate your Amplifa account/i, email.subject)

    html_body = email.html_part.body.to_s
    text_body = email.text_part.body.to_s

    assert_match 'Amplifa', html_body
    assert_match 'button', html_body
    assert_match '/verify-account?key=', html_body
    assert_match '/verify-account?key=', text_body
  end

  test 'verify account email respects account locale' do
    account = accounts(:customer_admin)
    account.update!(locale: 'de')

    email = RodauthMailer.verify_account(nil, account.id, 'test-verify-key')

    assert_match 'Aktivieren Sie Ihr Amplifa-Konto', email.subject
    assert_match 'Konto aktivieren', email.html_part.body.to_s
  end

  test 'reset password email respects account locale' do
    account = accounts(:customer_admin)
    account.update!(locale: 'de')

    email = RodauthMailer.reset_password(nil, account.id, 'test-reset-key')

    assert_match 'Setzen Sie Ihr Amplifa-Passwort zurück', email.subject
  end

  test 'email two factor renders branded transactional template' do
    account = accounts(:customer_admin)
    email = RodauthMailer.email_two_factor(nil, account.id, 'test-two-factor-token')

    assert_equal [account.email], email.to
    assert_match(/Complete your Amplifa sign in/i, email.subject)

    html_body = email.html_part.body.to_s
    text_body = email.text_part.body.to_s

    assert_match 'Amplifa', html_body
    assert_match 'button', html_body
    assert_match '/two-factor-email/verify?token=', html_body
    assert_match '/two-factor-email/verify?token=', text_body
  end

  test 'email two factor respects account locale' do
    account = accounts(:customer_admin)
    account.update!(locale: 'de')

    email = RodauthMailer.email_two_factor(nil, account.id, 'test-two-factor-token')

    assert_match 'Schließen Sie Ihre Amplifa-Anmeldung ab', email.subject
    assert_match 'Anmeldung abschließen', email.html_part.body.to_s
    assert_match 'Anmeldung bestätigen', email.text_part.body.to_s
  end
end
