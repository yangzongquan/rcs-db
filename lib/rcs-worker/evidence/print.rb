require_relative 'single_evidence'

module RCS
module PrintProcessing
  extend SingleEvidence

  def type
    :print
  end
end # ApplicationProcessing
end # DB
