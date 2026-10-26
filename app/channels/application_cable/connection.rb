module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin

    def connect
      self.current_admin = find_verified_admin
    end

    private

    def find_verified_admin
      admin = env['warden']&.user(:admin)
      return admin if admin

      reject_unauthorized_connection
    end
  end
end
