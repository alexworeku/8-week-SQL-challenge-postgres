SET search_path = foodie_fi;

/*------------------------
 * A. Customer Journey
 * -----------------------
 * Q#1. Based off the 8 sample customers provided in the sample from the subscriptions table, write a brief description about each customer’s onboarding journey.
 * Try to keep it as short as possible - you may also want to run some sort of join to make your explanations a bit easier!
 * 
 * Answer:
 * Customer 1: Started with a 1-week trial and upgraded to the Basic monthly plan after the trial ended.
 * Customer 2: Started with a 1-week trial and upgraded to the Pro annual plan after the trial ended.
 * Customer 3: Started with a 1-week trial and upgraded to the Basic monthly plan after the trial ended.
 * Customer 4: Started with a trial, upgraded to the Basic monthly plan, and churned after 3 months.
 * Customer 5: Started with a trial and upgraded to the Basic monthly plan.
 * Customer 6: Started with a trial, upgraded to the Basic monthly plan, and churned after 2 months.
 * Customer 7: Started with a trial, upgraded to the Basic monthly plan, and after 3 months upgraded again to the Pro monthly plan.
 * Customer 8: Started with a trial, moved to the Basic monthly plan, and after nearly 2 months upgraded to the Pro monthly plan.
 * */

select
	s.customer_id,
	p.plan_name,
	s.start_date 
from foodie_fi.subscriptions s 
join foodie_fi."plans" p on s.plan_id =p.plan_id 
where s.customer_id between 1 and 8
order by s.customer_id, s.start_date;


/**
 * -------------------------------
 * B. Data Analysis Questions
 * -------------------------------
 * 
 * Q1. How many customers has Foodie-Fi ever had?
 * */

select count(distinct customer_id)
from foodie_fi.subscriptions s ;

/*
 * Q2. What is the monthly distribution of trial plan start_date values for our dataset - use the start of the month as the group by value
 * */


select 
	date_trunc('month',s.start_date)::DATE as month,
	count(s.plan_id) as n_trial_plans
from foodie_fi.subscriptions s 
where s.plan_id = 0
group by date_trunc('month', s.start_date)
order by month asc;

/*
 * Q3. What plan start_date values occur after the year 2020 for our dataset? Show the breakdown by count of events for each plan_name
 * 
 * */

select 
	p.plan_name,
	count(s.plan_id) n_events      
from subscriptions s join plans p on s.plan_id =p.plan_id
where s.start_date > '2021-01-01'
group by p.plan_name
order by n_events desc;

/*
 *Q4. What is the customer count and percentage of customers who have churned rounded to 1 decimal place?
 * */

select 
	count(distinct s.customer_id) n_customers,
round( 100.0* count(distinct s.customer_id) filter (where s.plan_id=4) * 1.0 /
		count(distinct s.customer_id), 1) || '%'  as churn
from subscriptions s ;


/*
 *Q5. How many customers have churned straight after their initial free trial - what percentage is this rounded to the nearest whole number?
 * */
with customers_ranked as (
select 
	s.customer_id,
	s.plan_id,
	s.start_date,
	dense_rank() over (partition by s.customer_id order by s.start_date) as rnk
from subscriptions s
)
select 
	count(distinct cr.customer_id) as n_total_customers,
	count(*) filter (where cr.rnk=2 and cr.plan_id =4) as churn_after_trial,
	round(100.0 * count(*) filter (where cr.rnk = 2 and cr.plan_id =4)/ count(distinct cr.customer_id),0)||'%' as churn_percentage
from customers_ranked cr;


/*
 * Q6. What is the number and percentage of customer plans after their initial free trial?
 * */

with customers_ranked as (
select 
	s.customer_id,
	s.plan_id,
	s.start_date,
	dense_rank() over (partition by s.customer_id order by s.start_date) as rnk
from subscriptions s)
select 
	cr.plan_id,
	count(*) filter (where cr.rnk=2) as n_customer_plans_after_trial,
	count(distinct cr.customer_id) as n_customers
from customers_ranked cr
group by cr.plan_id;

