class ApplicationMailer < ActionMailer::Base
  default from: "Amplifa <#{ENV.fetch('MAILER_FROM', 'noreply@updates.amplifa.eu')}>"
  layout 'mailer'
end
