require 'pdf-reader'
require 'csv'

def clean(paragraphs)
  paragraphs.each do |paragraph|
   if paragraph.length > 1 
     paragraph.strip!
     paragraph.gsub! /^\s*/, "" if not paragraph.nil?
     paragraph.gsub! /\n/, " " if not paragraph.nil? 
   end
  end
  paragraphs
end

def filter(paragraphs)
  with_content = paragraphs.find_all {|x| !(x =~ /^\s*$/) }  
  not_page_titles = with_content.find_all {|x| !(x =~ /^FAIRFAX COUNTY SCHOOL BOARD$/) }  
  not_page_numbers = not_page_titles.find_all {|x| !(x =~ /^Regular Meeting No\./) }  

  not_page_numbers
end

def upper_case?(paragraph)
  result = false
  result = true if  paragraph =~ /^\s*[A-Z0-9\[]/
 
  result
end

def continuing_vote?(paragraph)
  result = false
  head = paragraph[0, 30]
  result = true if head =~ /,|and|voted|were|was absent/ && !(head =~ /moved/) 
end

def adjust(paragraphs)
  result = []
  i = 0
  while i < paragraphs.length do 
    paragraph = paragraphs[i]
    if not paragraph.nil? 
      if not upper_case? paragraph or continuing_vote? paragraph
        previous = (result.length > 0) ? result.pop : "" 
        paragraph =  previous << " " << paragraph
      end
=begin
      if not paragraph =~ /\.\s*\n$/
        next_paragraph = (i + 1 < paragraphs.length) ? paragraphs[i + 1] : ""
        paragraph << next_paragraph
        i +=1
      end
   
=end
      result << paragraph
    end
    i += 1
  end

  result
end

def find_votes(paragraphs)
  results = []
  key_words = /([Pp]assed|[Ff]ailed) (\d{1,2}-\d{1,2}(-\d{1,2})?|unanimously)/
  exclude = /a three-member committee/

  paragraphs.each do |candidate|
    if candidate =~ key_words && !(candidate =~ exclude)
      results << candidate
    end 
  end
  
  results
end

def get_paragraphs(file)
  reader = PDF::Reader.new(file)
  paragraphs = []

  reader.pages.each do |page|
    paragraphs <<  page.text.split(/\n\n/)
  end

  paragraphs.flatten!
end

def process(paragraphs)
  cleaned = clean paragraphs
  filtered = filter cleaned
  adjusted = adjust filtered
=begin 
  puts "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  adjusted.each do |paragraph|
    puts "++++++++++++++: " << paragraph
  end
=end
  adjusted
end

def parse(vote)
  result = {} 
  
  result["unanimous"] = (vote =~ /unanimously/) ? true : false
  result["passed"] = (vote =~ /[Pp]assed/)? true : false
  result = get_vote_count vote, result, result["unanimous"]
  result = get_member_vote vote, result
end

def get_member_vote(vote, result)
   members = ["Mr. Moon", "Ms. Evans",
  "Ms. Hynes", "Mr. McElveen",
  "Mr. Velkoff", "Ms. McLaughlin",
  "Ms. Schultz", "Mrs. Smith",
  "Mr. Storck", "Ms. Derenak Kaufax",
  "Mrs. Reed", "Mrs. Strauss" ]
 
  if result["unanimous"] == true
    result = tabulate_unanimous members, result 
  else 
    result = tease_out_votes vote, result
  end  

  result
end

def set_default(members, result)
 default = "n/a"
 members.each do |member| 
    result[member] = default
 end
end

def is_three_member_committee?(vote)
  result = false
  result = true if vote =~ /a three-member committee/
  result
end

def tabulate_unanimous(members, result)
  vote = result["passed"] ? "aye" : "nay" 
  result = unanimous_twelve members, result, vote
end

def unanimous_three(members, result, vote, vote_text)
  result = set_default members, result
  list = /along with (.*) moved/.match vote_text
  
  if  not list.nil?
    list = list[1].sub("and", ",")
    committee = list.split ","

    committee.each do |participant|
      result[participant.strip] = vote
    end
  end
  
  result
end

def unanimous_twelve(members, result, vote)
  members.each do |member|
    result[member] = vote
  end

  result
end

def tease_out_votes(vote, result)
  votes_pattern = /:\s+(M[rs]s?\..*)$/
  puts "the vote: "  << vote
  match = votes_pattern.match vote
  puts match.inspect 
  if not match.nil?
    votes = match[1].split ';'    
    votes.each do |members_vote|
 #    puts "member's vote " << members_vote
     vote = identify_vote members_vote
     members = get_members members_vote 
     members.each do |member|
       result[member.strip] = vote if member != ""
     end
    end
  end
  result
end

def get_members(members_vote)
  members_string = /(M[rs]s?\..*,?) (voted|were|was)?/ 
  match = members_string.match members_vote
 # puts "the votes: " << members_vote 
 # puts "the match: " << match.inspect

  members_list = match[1].sub "and", ","
  members_list.sub! /(voted|were|was).*$/, ","

 # puts  "the member list: " << members_list.inspect
  members = members_list.split ","
 
 # puts members
  members
end

def identify_vote(vote)
  result = "error" 

  if vote =~ /aye/
    result = "aye"
  elsif vote =~ /nay/
    result = "nay"
  elsif vote =~ /not present/
    result = "not present"
  elsif vote =~ /absent/
    result = "absent"
  elsif vote =~ /abstained/
    result = "abstained"
  end

  result
end

def get_vote_count(vote, result, unanimous)
  vote_pattern = /([Pp]assed|[Ff]ailed) (\d{1,2}-\d{1,2}(-\d{1,2})?|unanimously):/
  
  if unanimous 
    if result["passed"]
      result["yeas"] = 12 
      result["nays"] = 0 
      result["absent"] = 0
    else 
      result["yeas"] = 0
      result["nays"] = 12 
      result["absent"] = 0
    end
 else 
  count = vote_pattern.match vote
  
  if not count.nil?
    result["count"] = count[2].to_s
     
    vote_count = count[2].to_s.split "-"

    result["yeas"] = vote_count[0]
    result["nays"] = vote_count[1] if vote_count.count == 2
    result["absent"] = vote_count[2] if vote_count.count == 3
  end
 end
 result
end

def to_csv(votes, date)
  CSV.open("school_board.csv", "a:utf-8") do |csv| 
    votes.each do |vote|
      #puts "the vote from votes :" << vote
      parsed = parse vote

      puts "********\n#{parsed.inspect}\n***********\n"
      #puts ".......\n#{vote}\n..........\n"
      csv << ["#{date}","#{vote}",  
              "#{parsed["passed"]}", "#{parsed["unanimous"]}", 
              "\"#{parsed["count"]}\"", "#{parsed["yeas"]}", 
              "#{parsed["nays"]}", "#{parsed["absent"]}",
              "#{parsed["Mr. Moon"]}", "#{parsed["Ms. Evans"]}",
              "#{parsed["Ms. Hynes"]}", "#{parsed["Mr. McElveen"]}",
              "#{parsed["Mr. Velkoff"]}", "#{parsed["Ms. McLaughlin"]}",
              "#{parsed["Ms. Schultz"]}", "#{parsed["Mrs. Smith"]}",
              "#{parsed["Mr. Storck"]}", "#{parsed["Ms. Derenak Kaufax"]}",
              "#{parsed["Mrs. Reed"]}", "#{parsed["Mrs. Strauss"]}",
     
      ]
    end
  end
end

def get_date(paragraph)
  result = nil

  paragraph.each do |paragraph| 
    if paragraph =~ /^Regular Meeting No\./ 
      parts = paragraph.split /\s{2,}\d{0,3}\s{2,}/ 

      result = parts[1].strip 
      break  
    end
  end

  result
end

def get_votes(file)
  paragraphs = get_paragraphs file
  date = get_date paragraphs
  clean_paragraphs = process paragraphs

  votes = find_votes clean_paragraphs
  to_csv votes, date
end

def create_csv
  CSV.open("school_board.csv", "w:utf-8") do |csv| 
    csv << ["date","raw", "passed?", "unanimous?", "vote", "yeas", "nays", "absent", "Moon", "Evans","Hynes", "mcElveen", "Velkoff", "McLaughlin", "Schultz", "Smith", "Storck", "Derenak Kaufax", "Reed", "Strauss" ]
  end
end

def gather()
  create_csv
  Dir.entries(".").each do |file|
    if file =~ /\.pdf$/i  
      get_votes file
    end
  end
end

gather
