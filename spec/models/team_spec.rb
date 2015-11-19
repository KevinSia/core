# == Schema Information
#
# Table name: teams
#
#  id                               :integer          not null, primary key
#  name                             :string(255)      not null
#  slug                             :string(255)
#  url                              :string(255)
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  cloudinary_id                    :string(255)
#  bio                              :text
#  featured                         :boolean          default(FALSE), not null
#  linked_account_id                :integer
#  accepts_public_payins            :boolean          default(FALSE), not null
#  rfp_enabled                      :boolean          default(FALSE), not null
#  activity_total                   :decimal(, )      default(0.0), not null
#  bounties_disabled                :boolean
#  support_level_sum                :decimal(10, 2)
#  support_level_count              :integer
#  homepage_markdown                :text
#  homepage_featured                :integer
#  accepts_issue_suggestions        :boolean          default(FALSE), not null
#  new_issue_suggestion_markdown    :text
#  bounty_search_markdown           :text
#  resources_markdown               :text
#  monthly_contributions_sum        :decimal(10, 2)
#  monthly_contributions_count      :integer
#  can_email_stargazers             :boolean          default(FALSE), not null
#  previous_month_contributions_sum :decimal(10, 2)
#
# Indexes
#
#  index_companies_on_slug           (slug) UNIQUE
#  index_teams_on_activity_total     (activity_total)
#  index_teams_on_homepage_featured  (homepage_featured)
#  index_teams_on_linked_account_id  (linked_account_id)
#

require 'spec_helper'

describe Team do

  let(:person) { create :person }
  let(:team) { create :team }
  let(:tracker) { create :tracker }

  it "should require name" do
    team = Team.create
    team.errors.should have_key :name
  end


  it "should have an enterprise account" do
    team.build_account.should be_a Account::Team
  end

  it "should add person" do
    lambda {
      team.add_member(person)
    }.should change(team.members, :count).by 1
  end

  it "should default public to true" do
    new_member = team.add_member(person)
    team.reload
    team.person_is_public?(new_member)
  end

  it "should add person as developer" do
    new_member = team.add_member(person, developer: true)
    team.person_is_developer?(new_member)
  end

  it "should add person as admin" do
    new_member = team.add_member(person, admin: true)
    team.person_is_admin?(new_member)
  end

  it "should add tracker" do
    team.add_tracker(tracker)
    team.trackers.should include tracker
  end

  it "should set slug" do
    lambda {
      team.update_attributes(slug: "adobe")
    }.should change(team, :slug).to "adobe"
  end

  it "should send email to member when added to team" do
    new_member = create(:person)
    new_member.should_receive(:send_email).with(:added_to_team, anything).once
    team.add_member(new_member)
  end

  describe "slug uniqueness" do
    let!(:team) { create(:team, slug: "adobe") }

    it "should require unique slug to create" do
      expect {
        Team.create(name: team.name)
      }.not_to change(Team, :count)
    end

    it "should require unique slug to update" do
      new_team = create(:team, slug: "totally-unique")
      expect {
        new_team.update_attributes(slug: team.slug)
      }.not_to change(new_team, :name)
    end
  end

  context "tracker added" do
    before { team.add_tracker(tracker) }

    it "should remove tracker" do
      lambda {
        team.trackers.delete(tracker)
      }.should change(team.trackers, :count).by -1
    end

    it "should NOT delete the Tracker model" do
      lambda {
        team.trackers.delete(tracker)
      }.should_not change(Tracker, :count)
    end
  end

  describe "invite member" do
    let(:member) { create(:person) }

    it "should create invite" do
      expect {
        team.invite_member(member.email)
        team.reload
      }.to change(team.invites, :count).by 1
    end

    it "should not add member yet" do
      expect {
        team.invite_member(member.email)
        team.reload
      }.not_to change(team.members, :count)
    end

    it "should send email on invite" do
      TeamInvite.any_instance.should_receive(:send_email).once
      team.invite_member(member.email)
    end
  end

  describe "manage_issue?" do
    let!(:owned_tracker) { create(:tracker, team: team) }
    let(:issue) { create(:issue, tracker: owned_tracker)}

    it "should check if the issue belongs to a tracker that the team owns" do
      team.stub_chain(:owned_trackers, :pluck).and_return([owned_tracker.id])
      team.manage_issue?(issue).should eq (true)
    end
  end

  describe "merge" do
    let(:person1) { create(:person)}
    let(:person2) { create(:person)}
    let(:team1) { create(:team)}
    let(:team2) { create(:team)}
    it "should not duplicate tag votes" do
      company_tag = Tag.create(name: "Companies")
      lang_tag = Tag.create(name: "Languages")

      # person 1 tags team1 with companies+languages and team2 with companies
      team1.parent_tag_relations.where(child: company_tag).first_or_create.votes.create(person: person1, value: 1)
      team1.parent_tag_relations.where(child: lang_tag).first_or_create.votes.create(person: person1, value: 1)
      team2.parent_tag_relations.where(child: company_tag).first_or_create.votes.create(person: person1, value: 1)
      TagRelation.count.should eq(3)
      TagVote.count.should eq(3)
      team1.parent_tag_relations.where(child: company_tag).first.weight.should eq(1)
      team1.parent_tag_relations.where(child: lang_tag).first.weight.should eq(1)
      team2.parent_tag_relations.where(child: company_tag).first.weight.should eq(1)

      # person 2 tags team 1 with languages
      team1.parent_tag_relations.where(child: lang_tag).first_or_create.votes.create(person: person2, value: 1)
      TagRelation.count.should eq(3)
      TagVote.count.should eq(4)
      team1.parent_tag_relations.where(child: company_tag).first.weight.should eq(1)
      team1.parent_tag_relations.where(child: lang_tag).first.weight.should eq(2)
      team2.parent_tag_relations.where(child: company_tag).first.weight.should eq(1)

      # teams get merged and new team should have 1 vote for companies and 2 for lang
      Team.merge!(team1,team2)
      TagRelation.count.should eq(2)
      TagVote.count.should eq(3)
      team1.parent_tag_relations.where(child: company_tag).first.weight.should eq(1)
      team1.parent_tag_relations.where(child: lang_tag).first.weight.should eq(2)
    end
  end
end