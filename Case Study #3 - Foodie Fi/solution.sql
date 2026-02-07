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
	dense_rank() over (partition by s.customer_id order by s.start_date) as rnk,
	p.plan_name
from subscriptions s
join plans p on s.plan_id = p.plan_id
)
select 
	cr.plan_id,
	cr.plan_name,
	count(*) as n_customer_after_trial,
	round(100.0*count(*) filter (where cr.rnk=2)/(select count(distinct cr2.customer_id) from customers_ranked cr2),1) as percentage
from customers_ranked cr
where cr.rnk=2
group by cr.plan_id,cr.plan_name
order by percentage desc;


--with customers as ()
with customer_next_plan_cte as (
select 
	s.plan_id as current_plan_id,

	s.customer_id, 
	s.start_date,
	lead(s.plan_id,1) over (partition by s.customer_id order by s.start_date) as next_plan_id
from subscriptions s
)

select 
	p.plan_name,
	count(*) as converstion_count,
	100.0 * count(*)/sum(count(*)) over() as percentage
	
from customer_next_plan_cte cnp  join plans p on p.plan_id = cnp.next_plan_id
where cnp.current_plan_id=0 and cnp.next_plan_id is not null
group by cnp.next_plan_id, p.plan_name
order by percentage desc;



/*
 * Q7 What is the customer count and percentage breakdown of all 5 plan_name values at 2020-12-31?
 */

with customer_plan_cte as (
select 
	s.plan_id as current_plan_id,
	lead(s.plan_id,1) over (partition by s.customer_id order by s.start_date) as next_plan_id,
	s.start_date
from subscriptions s 
where s.start_date <='2020-12-31'
)
select 
	
	p.plan_name,
	count(*) as converstion_count,
	100.0 * count(*)/sum(count(*)) over() as percentage
	
from customer_plan_cte cp join plans p on p.plan_id = cp.current_plan_id 
where cp.next_plan_id is null

group by cp.current_plan_id, p.plan_name;


/*
 *Q8 How many customers have upgraded to an annual plan in 2020?
 */

select
	count(distinct s.customer_id) as n_customers
from subscriptions s
where date_part('year', s.start_date)=2020 and s.plan_id=3;

select *
from plans p;
/*
*Q9 How many days on average does it take for a customer to an annual plan from the day they join Foodie-Fi?
*/
-- works, but can't handle edge cases where there is no trial
with customers_annual_plan_cte as (

select 
	s.customer_id,
	s.plan_id, 
	s.start_date,
	lead(s.start_date) over(partition by s.customer_id order by s.start_date) as annual_start_date
from subscriptions s
where s.plan_id=0  or s.plan_id =3)
select 

	round(avg(cap.annual_start_date - cap.start_date) ,2) as avg_num_of_days_till_annual_sub

from customers_annual_plan_cte cap
where cap.annual_start_date is not null;

-- better approach

select 
	round(avg(annual.start_date - trial.start_date),2) as avg_day_till_annual_sub
from subscriptions trial
join subscriptions annual on trial.customer_id = annual.customer_id
where trial.plan_id = 0 and annual.plan_id=3;


/*
 * Can you further breakdown this average value into 30 day periods (i.e. 0-30 days, 31-60 days etc)
 */