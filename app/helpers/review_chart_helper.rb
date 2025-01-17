module ReviewChartHelper
  # moves data of reviews in each round from a current round
  def initialize_chart_elements(reviewer)
    labels, reviewer_data, all_reviewers_data = [], [], []
    @num_rounds.times do |rnd|
      next if @all_reviewers_avg_vol_per_round[rnd] <= 0
      labels << (rnd + 1)
      reviewer_data << reviewer.avg_vol_per_round[rnd]
      all_reviewers_data << @all_reviewers_avg_vol_per_round[rnd]
    end
    labels << 'Total'
    reviewer_data << reviewer.overall_avg_vol
    all_reviewers_data << @all_reviewers_overall_avg_vol
    [labels, reviewer_data, all_reviewers_data]
  end

  # The data of all the reviews is displayed in the form of a bar chart
  def display_volume_metric_chart(reviewer)
    labels, reviewer_data, all_reviewers_data =
      initialize_chart_elements(reviewer)
    data = build_chart_data(labels, reviewer_data, all_reviewers_data)
    options = build_chart_options
    horizontal_bar_chart(data, options)
  end

  # Get chart labels and datasets
  def build_chart_data(labels, reviewer_data, all_reviewers_data)
    {
      labels: labels,
      datasets: [
        build_chart_dataset(
          'vol.',
          'rgba(255,99,132,0.8)',
          reviewer_data, 'bar-y-axis1'
        ),
        build_chart_dataset(
          'avg. vol.',
          'rgba(255,206,86,0.8)',
          all_reviewers_data,
          'bar-y-axis2'
        )
      ]
    }
  end

  # Get list of chart datasets
  def build_chart_dataset(label, color, data, y_axis_id)
    {
      label: label,
      backgroundColor: color,
      borderWidth: 1,
      data: data,
      yAxisID: y_axis_id
    }
  end

  def build_chart_options
    {
      legend: { position: 'top', labels: { usePointStyle: true } },
      width: '200', height: '125',
      scales: {
        yAxes: [
          build_chart_y_axis('bar-y-axis1', 10),
          build_chart_y_axis('bar-y-axis2', 15, true)
        ],
        xAxes: [
          {
            stacked: false,
            ticks: { beginAtZero: true, stepSize: 50, max: 400 }
          }
        ]
      }
    }
  end

  # Configure the y axis of the chart
  def build_chart_y_axis(id, bar_thickness, display = false)
    {
      display: display,
      stacked: true,
      id: id,
      barThickness: bar_thickness,
      type: 'category',
      categoryPercentage: 0.8,
      barPercentage: 0.9,
      gridLines: { offsetGridLines: true }
    }
  end

  # E2082 Generate chart for review tagging time intervals
  def display_tagging_interval_chart(intervals)
    threshold = 30
    intervals = intervals.select { |v| v < threshold }
    interval_mean = intervals.sum / intervals.size.to_f unless intervals.empty?
    data = build_tagging_chart_data(intervals, interval_mean)
    options = tagging_chart_options
    line_chart(data, options)
  end

  # Build tagging chart data
  def build_tagging_chart_data(intervals, interval_mean)
    {
      labels: [*1..intervals.length],
      datasets: [
        {
          backgroundColor: 'rgba(255,99,132,0.8)',
          data: intervals, label: 'time intervals'
        },
        *interval_mean && [
          {
            data: [interval_mean] * intervals.length,
            label: 'Mean time spent'
          }
        ]
      ]
    }
  end

  def tagging_chart_options
    {
      width: '200', height: '125',
      scales: {
        yAxes: [{ stacked: false, ticks: { beginAtZero: true } } ],
        xAxes: [{ stacked: false }]
      }
    }
  end

  # Calculate mean for tagging intervals
  def calculate_mean(intervals, interval_precision)
    mean = intervals.sum / intervals.size.to_f
    mean.round(interval_precision)
  end

  # Calculate variance for tagging intervals
  def calculate_variance(intervals, interval_precision)
    mean = intervals.sum / intervals.size.to_f
    variance = intervals.sum { |v| (v - mean)**2 } / intervals.size.to_f
    variance.round(interval_precision)
  end

  # Calculate standard deviation for tagging intervals
  def calculate_standard_deviation(intervals, interval_precision)
    mean = intervals.sum / intervals.size.to_f
    variance = intervals.sum { |v| (v - mean)**2 } / intervals.size.to_f
    Math.sqrt(variance).round(interval_precision)
  end

  # Calculate mean,min,max,variance and stand deviation for tagging intervals
  def calculate_key_chart_information(intervals)
    threshold, interval_precision = 30, 2
    valid_intervals = intervals.select { |v| v < threshold }
    return nil if valid_intervals.empty?
    {
      mean: calculate_mean(valid_intervals, interval_precision),
      min: valid_intervals.min,
      max: valid_intervals.max,
      variance: calculate_variance(valid_intervals, interval_precision),
      stand_dev: calculate_standard_deviation(valid_intervals, interval_precision)
    }
  end
end
