# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_account

    def connect
      self.current_account = find_verified_account
    end

    private

    def find_verified_account
      account_id = request.session[:account_id]
      account = Account.find_by(id: account_id) if account_id

      if account
        account
      else
        reject_unauthorized_connection
      end
    end
  end
end
