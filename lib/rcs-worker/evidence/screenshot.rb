require_relative 'single_evidence'

module RCS
module ScreenshotProcessing
  extend SingleEvidence

  def type
    :screenshot
  end
end # ApplicationProcessing
end # DB
