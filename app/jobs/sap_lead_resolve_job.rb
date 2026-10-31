class SapLeadResolveJob < ApplicationJob
  def perform
    SapLead::Resolver.new.run
    SapLead::Registrar.new.run
  end
end
