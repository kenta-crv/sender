class SapLeadResolveJob < ApplicationJob
  def perform
    SapLead::Resolver.new.run
  end
end
