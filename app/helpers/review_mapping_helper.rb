module ReviewMappingHelper
  def create_report_table_header(headers = {})
    render partial: 'report_table_header', locals: { headers: headers }
  end
  
  # gets the response map data of reviewer id, reviewed object id and type for the review report 
  def review_report_data(reviewed_object_id, reviewer_id, type)
    response_maps = ResponseMap.where(reviewed_object_id: reviewed_object_id, reviewer_id: reviewer_id, type: type)
    response_counts = calculate_response_counts(response_maps)
    response_maps_with_counts = response_maps.select { |response_map| Team.exists?(id: response_map.reviewee_id) }
    [response_maps_with_counts, response_maps_with_counts.size, response_counts]
  end
  
  # calculates the response counts for each round
  def calculate_response_counts(response_maps)
    (1..@assignment.num_review_rounds).map do |round|
      response_maps.count { |response_map| response_map.response.exists?(round: round) }
    end
  end


  # gets the team name's color according to review and assignment submission status
  def get_team_color(response_map)
    if Response.exists?(map_id: response_map.id)
      if !response_map.try(:reviewer).try(:review_grade).nil?
        return 'brown'
      elsif response_for_each_round?(response_map)
        return 'blue'
      end
    else
      return 'red'
    end
    obtain_team_color(response_map, @assignment.created_at, DueDate.where(parent_id: response_map.reviewed_object_id))
  end
  
  # loops through the number of assignment review rounds and obtains the team colour
  def obtain_team_color(response_map, assignment_created, assignment_due_dates)
    # We will store the colors in this array.
    colors = []
    # Loop through each round of review.
    (1..@assignment.num_review_rounds).each do |round|
      # Call the check_submission_state method to get the color for the current round.
      check_submission_state(response_map, assignment_created, assignment_due_dates, round, colors)
    end
    # Return the color for the latest round.
    colors.last
  end


  # checks the submission state within each round and assigns team colour
  def check_submission_state(response_map, assignment_created, assignment_due_dates, round, colors)
    if submitted_within_round?(round, response_map, assignment_created, assignment_due_dates)
      colors.push('purple')
    else
      link = submitted_hyperlink(round, response_map, assignment_created, assignment_due_dates)    
      if link.nil? || !link.start_with?('https://wiki')
        colors.push('green')
      else
        link_updated_at = last_modified_date_for_link(link)
        if link_updated_since_last?(round, assignment_due_dates, link_updated_at)
          colors.push('purple')
        else
          colors.push('green')
        end
      end
    end
  end
  
  # checks if a review was submitted in every round and gives the total responses count
  def response_for_each_round?(response_map)
    num_responses = 0
    total_num_rounds = @assignment.num_review_rounds
    (1..total_num_rounds).each do |round|
      num_responses += 1 if Response.exists?(map_id: response_map.id, round: round)
    end
    num_responses == total_num_rounds
  end

  # checks if a work was submitted within a given round
  def submitted_within_round?(round, response_map, assignment_created, assignment_due_dates)
    submission_due_date = assignment_due_dates.where(round: round, deadline_type_id: 1).try(:first).try(:due_at)  
    submission = SubmissionRecord.where(team_id: response_map.reviewee_id, operation: ['Submit File', 'Submit Hyperlink'])
    if round > 1
      submission_due_last_round = assignment_due_dates.where(round: round - 1, deadline_type_id: 1).try(:first).try(:due_at)
      submission = submission.where(created_at: submission_due_last_round..submission_due_date)
    else
      submission = submission.where(created_at: assignment_created..submission_due_date)
    end
    submission.exists?
  end
  
  # returns hyperlink of the assignment that has been submitted on the due date
  def submitted_hyperlink(round, response_map, assignment_created, assignment_due_dates)
    submission_due_date = assignment_due_dates.where(round: round, deadline_type_id: 1).try(:first).try(:due_at)
    subm_hyperlink = SubmissionRecord.where(team_id: response_map.reviewee_id, operation: 'Submit Hyperlink')
    submitted_h = subm_hyperlink.where(created_at: assignment_created..submission_due_date)
    submitted_h.try(:last).try(:content)
  end

  # returns last modified header date
  # only checks certain links (wiki)
  def last_modified_date_for_link(link)
    uri = URI(link)
    res = Net::HTTP.get_response(uri)['last-modified']
    res.to_time
  end

  # checks if a link was updated since last round submission
  def link_updated_since_last?(round, due_dates, link_updated_at)
    submission_due_date = due_dates.where(round: round, deadline_type_id: 1).try(:first).try(:due_at)
    submission_due_last_round = due_dates.where(round: round - 1, deadline_type_id: 1).try(:first).try(:due_at)
    (link_updated_at < submission_due_date) && (link_updated_at > submission_due_last_round)
  end

  # For assignments with 1 team member, the following method returns user's fullname else it returns "team name" that a particular reviewee belongs to.
  def reviewed_link_name_for_team(max_team_size, _response, reviewee_id, ip_address)
    team_reviewed_link_name = if max_team_size == 1
                                TeamsUser.where(team_id: reviewee_id).first.user.fullname(ip_address)
                              else
                                # E1991 : check anonymized view here
                                Team.find(reviewee_id).name
                              end
    team_reviewed_link_name = '(' + team_reviewed_link_name + ')'
    # if !response.empty? and !response.last.is_submitted?
    team_reviewed_link_name
  end

  # gets the review score awarded based on each round of the review
  def awarded_review_score(reviewer_id, team_id)
    num_rounds = @assignment.num_review_rounds
    round_variable_names = (1..num_rounds).map { |round| "@score_awarded_round_#{round}" }
    round_variable_names.each { |name| instance_variable_set(name, '-----') }
    return if team_id.nil? || team_id == -1.0
    (1..num_rounds).each do |round|
      # Changing values of instance variable based on below condition
      if @review_scores[reviewer_id] && @review_scores[reviewer_id][round] && @review_scores[reviewer_id][round][team_id] && @review_scores[reviewer_id][round][team_id] != -1.0
        instance_variable_set('@score_awarded_round_' + round.to_s, @review_scores[reviewer_id][round][team_id].to_s + '%')
      end
    end
  end
  
  
  
  # gets minimum, maximum and average grade value for all the reviews present
  def review_metrics(round, team_id)
    %i[max min avg].each do |metric|
      instance_variable_set("@#{metric}", '-----')
    end
    avg_and_ranges = @avg_and_ranges&.dig(team_id, round)
    if avg_and_ranges && avg_and_ranges.values_at(:max, :min, :avg).all?(&:present?)
      avg_and_ranges.each do |metric, value|
        metric_value = "#{value.round(0)}%"
        instance_variable_set("@#{metric}", metric_value)
      end
    end
  end

  # sorts the reviewers by the average volume of reviews in each round, in descending order
  def sort_reviewer_by_review_volume_desc
    # Get the volume of review comments for each reviewer
    @reviewers.each do |reviewer|
      reviewer.avg_vol_per_round = []
      review_volumes = Response.volume_of_review_comments(@assignment.id, reviewer.id)
      reviewer.overall_avg_vol = review_volumes.first
      reviewer.avg_vol_per_round.concat(review_volumes[1..-1])
    end
    # Sort reviewers by their review volume in descending order
    @reviewers.sort_by! { |reviewer| -reviewer.overall_avg_vol }
    # Get the number of review rounds for the assignment
    @num_rounds = @assignment.num_review_rounds.to_i
    @all_reviewers_avg_vol_per_round = []
  end
  
  
  def list_review_submissions(participant_id, reviewee_team_id, response_map_id)
    participant = Participant.find(participant_id)
    team = AssignmentTeam.find(reviewee_team_id)
    html = ''
    if review_submissions_available?(team, participant)
      review_submissions_path = team.path + '_review' + '/' + response_map_id.to_s
      files = team.submitted_files(review_submissions_path)
      html += display_review_files_directory_tree(participant, files) if files.present?
    end
    html.html_safe
  end
  
  def review_submissions_available?(team, participant)
    team.present? && participant.present?
  end
  

  # Zhewei - 2016-10-20
  # This is for Dr.Kidd's assignment (806)
  # She wanted to quickly see if students pasted in a link (in the text field at the end of the rubric) without opening each review
  # Since we do not have hyperlink question type, we hacked this requirement
  # Maybe later we can create a hyperlink question type to deal with this situation.
  def list_hyperlink_submission(response_map_id, question_id)
    assignment = Assignment.find(@id)
    curr_round = assignment.try(:num_review_rounds)
    curr_response = Response.where(map_id: response_map_id, round: curr_round).first
    answer_with_link = Answer.where(response_id: curr_response.id, question_id: question_id).first if curr_response
    comments = answer_with_link.try(:comments)
    html = ''
    html += display_hyperlink_in_peer_review_question(comments) if comments.present? && comments.start_with?('http')
    html.html_safe
  end

  # gets review and feedback responses for all rounds for the feedback report
  def calculate_review_and_feedback_responses(author)
    @team_id = TeamsUser.team_id(@id.to_i, author.user_id)
    # Calculate how many responses one team received from each round
    # It is the feedback number each team member should make
    @review_response_map_ids = ReviewResponseMap.where(['reviewed_object_id = ? and reviewee_id = ?', @id, @team_id]).pluck('id')
    feedback_response_map_record(author)
    # rspan means the all peer reviews one student received, including unfinished one
    @rspan_round_one = @review_responses_round_one.length
    @rspan_round_two = @review_responses_round_two.length
    @rspan_round_three = @review_responses_round_three.nil? ? 0 : @review_responses_round_three.length
  end

  # This function sets the values of instance variable
  def feedback_response_map_record(author)
    { 1 => 'one', 2 => 'two', 3 => 'three' }.each do |key, round_num|
      instance_variable_set('@review_responses_round_' + round_num,
                            Response.where(['map_id IN (?) and round = ?', @review_response_map_ids, key]))
      # Calculate feedback response map records
      instance_variable_set('@feedback_response_maps_round_' + round_num,
                            FeedbackResponseMap.where(['reviewed_object_id IN (?) and reviewer_id = ?',
                                                       instance_variable_get('@all_review_response_ids_round_' + round_num), author.id]))
    end
  end

  # gets review and feedback responses for a certain round for the feedback report
  def get_certain_review_and_feedback_response_map(author)
    # Setting values of instance variables
    @feedback_response_maps = FeedbackResponseMap.where(['reviewed_object_id IN (?) and reviewer_id = ?', @all_review_response_ids, author.id])
    @team_id = TeamsUser.team_id(@id.to_i, author.user_id)
    @review_response_map_ids = ReviewResponseMap.where(['reviewed_object_id = ? and reviewee_id = ?', @id, @team_id]).pluck('id')
    @review_responses = Response.where(['map_id IN (?)', @review_response_map_ids])
    @rspan = @review_responses.length
  end

  #
  # for calibration report
  #
  def css_class_for_calibration_report(diff)
    # diff - difference between stu's answer and instructor's answer
    dict = { 0 => 'c5', 1 => 'c4', 2 => 'c3', 3 => 'c2' }
    css_class = if dict.key?(diff.abs)
                  dict[diff.abs]
                else
                  'c1'
                end
    css_class
  end

  class ReviewStrategy
    attr_accessor :participants, :teams

    def initialize(participants, teams, review_num)
      @participants = participants
      @teams = teams
      @review_num = review_num
    end
  end

  class StudentReviewStrategy < ReviewStrategy
    def reviews_per_team
      (@participants.size * @review_num * 1.0 / @teams.size).round
    end

    def reviews_needed
      @participants.size * @review_num
    end

    def reviews_per_student
      @review_num
    end
  end

  class TeamReviewStrategy < ReviewStrategy
    def reviews_per_team
      @review_num
    end

    def reviews_needed
      @teams.size * @review_num
    end

    def reviews_per_student
      (@teams.size * @review_num * 1.0 / @participants.size).round
    end
  end
end
