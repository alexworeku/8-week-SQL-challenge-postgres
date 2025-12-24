set search_path to dannys_diner;

-- 1. What is the total amount each customer spent at the restaurant?

select s.customer_id as customer, sum(m.price) as total
from sales s join menu m on s.product_id = m.product_id
group by s.customer_id;

-- 2. How many days has each customer visited the restaurant?

 select s.customer_id, count(distinct s.order_date) as n_visited
 from sales s
 group by s.customer_id;

-- 3. What was the first item from the menu purchased by each customer?


 select s.customer_id, s.product_id, m.product_name
 from sales s join menu m on s.product_id = m.product_id
 where s.order_date = (
 select min(s2.order_date)
   from sales s2
   where s2.customer_id = s.customer_id
 );


-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?

 with ranked_products as (
 select 
   s.product_id, 
   count(*) as n_purchase,
   rank() over (order by count(*) desc) as rnk  
 from sales s
 group by s.product_id
 )

select 
	 rp.product_id, 
	 m.product_name, 
	 rp.n_purchase
from ranked_products rp 
	join menu m on rp.product_id = m.product_id
where rnk=1;

-- 5. Which item was the most popular for each customer?

with item_count_by_customer as(
select s.customer_id,
	s.product_id,  
	count(*) as n_sale,
	rank() over (
	partition by s.customer_id
	order by count(*) desc) as rnk

from sales s 
group by s.customer_id, s.product_id
)

select ic.customer_id, m.product_name, ic.n_sale
from item_count_by_customer ic join menu m on ic.product_id = m.product_id
where ic.rnk=1;


-- 6. Which item was purchased first by the customer after they became a member?

select s.customer_id, s.order_date, mn.product_name
from sales s join members m on s.customer_id = m.customer_id
join menu mn on mn.product_id = s.product_id
where  s.order_date = (

select min(s2.order_date)
from sales s2
where s2.customer_id = s.customer_id and s2.order_date >= m.join_date 
);


with first_purchased_items as (
select
s.customer_id,
mn.product_name,
s.order_date,
dense_rank() over ( 
partition by s.customer_id
order by s.order_date asc) as rnk
from sales s join members m on s.customer_id = m.customer_id
join menu mn on mn.product_id = s.product_id)

select  
fpi.customer_id,
fpi.product_name,
fpi.order_date
from first_purchased_items fpi
where fpi.rnk = 1;

-- 7. Which item was purchased just before the customer became a member?

with last_purchased_items_before_membership as (
select
s.customer_id,
mn.product_name,
s.order_date, 
dense_rank() over(
partition by s.customer_id
order by s.order_date desc
) as rnk
from sales s join members m on s.customer_id = m.customer_id
join menu mn on mn.product_id = s.product_id
where s.order_date < m.join_date)

select 
	lpibm.customer_id,
	lpibm.product_name,
	lpibm.order_date
from last_purchased_items_before_membership lpibm
where rnk = 1;



-- 8. What is the total items and amount spent for each member before they became a member?

select
s.customer_id,
count(*) as total_items,
sum(mn.price) as total_amount_spent

from sales s join members m on s.customer_id = m.customer_id
join menu mn on mn.product_id = s.product_id

where s.order_date < m.join_date
group by s.customer_id;


-- 9.  If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?

with sales_with_points as (
select
	s.customer_id, 
	m.product_name, 
	m.price,
	case product_name
		when 'sushi' then 2 * (m.price * 10)
		else m.price * 10
	end as points
from sales s join menu m on s.product_id = m.product_id
)

select 
	swp.customer_id, 
	sum(swp.price) as total_spent,
	sum(swp.points) as points_earned
from sales_with_points swp
group by swp.customer_id
order by points_earned desc;


-- 10. In the first week after a customer joins the program (including their join date) they earn 2x points on all items, 
-- not just sushi - how many points do customer A and B have at the end of January?


with sales_with_points as (
select
	s.customer_id,
	m.price,
	s.order_date,
	mem.join_date,
	case
		when s.order_date >=mem.join_date and s.order_date::date - mem.join_date::date <=7 then 2* (m.price * 10)
		else m.price * 10
	end as points
	

from sales s join menu m on s.product_id = m.product_id
join members mem on mem.customer_id = s. customer_id
)

select 
	swp.customer_id,
	sum(swp.points) as points_earned
from sales_with_points swp
where extract(month from swp.order_date) = 1
group by swp.customer_id
order by points_earned desc;





